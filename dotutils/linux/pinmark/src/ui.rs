use std::{
    collections::HashMap, io, os::unix::net::UnixListener, path::PathBuf, sync::Arc, thread,
};

use calloop::{channel, generic::Generic, EventLoop, Interest, Mode, PostAction};
use calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_layer, delegate_output, delegate_pointer, delegate_registry,
    delegate_seat, delegate_shm,
    output::{OutputHandler, OutputInfo, OutputState},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        pointer::{
            CursorIcon, PointerEvent, PointerEventKind, PointerHandler, ThemeSpec, ThemedPointer,
        },
        Capability, SeatHandler, SeatState,
    },
    shell::{
        wlr_layer::{
            Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
            LayerSurfaceConfigure,
        },
        WaylandSurface,
    },
    shm::{slot::SlotPool, Shm, ShmHandler},
};
use tiny_skia::Pixmap;
use wayland_client::{
    globals::registry_queue_init,
    protocol::{wl_keyboard, wl_output, wl_pointer, wl_registry, wl_seat, wl_shm, wl_surface},
    Connection, Dispatch, QueueHandle, WEnum,
};
use wayland_protocols::wp::{
    relative_pointer::zv1::client::{zwp_relative_pointer_manager_v1, zwp_relative_pointer_v1},
    viewporter::client::{wp_viewport, wp_viewporter},
};

use crate::{
    backend::{self, Monitor, Runner, Screenshot, TaskError},
    geometry::{toolbar_rect, Drag, Markings, Point, Rect, Tool, TOOLBAR_HEIGHT, TOOLBAR_WIDTH},
    ipc::{self, Request},
    pins::{PinId, PinStore},
    render::{self, Button, CopyState},
    save,
};

#[derive(Debug)]
enum WorkerMessage {
    Captured(u64, Result<Screenshot, TaskError>),
    Copied(PinId, Result<(), TaskError>),
    Saved(PinId, Result<Option<PathBuf>, TaskError>),
    Quit,
}

#[derive(Clone, Copy)]
enum SurfaceKind {
    Image,
    Toolbar,
}

struct NativeLayer {
    layer: LayerSurface,
    viewport: wp_viewport::WpViewport,
    logical_size: (u32, u32),
    ready: bool,
    waiting_frame: bool,
    dirty: bool,
}
impl Drop for NativeLayer {
    fn drop(&mut self) {
        self.viewport.destroy();
    }
}

struct Viewer {
    output: wl_output::WlOutput,
    monitor: Rect,
    region: Rect,
    image: NativeLayer,
    toolbar: NativeLayer,
}

struct Document {
    screenshot: Screenshot,
    markings: Markings,
    offset: (i32, i32),
}

struct Card {
    document: Document,
    viewer: Option<Viewer>,
    hover: Option<Button>,
    pressed: Option<Button>,
    copy_state: CopyState,
    save_state: CopyState,
}
impl Card {
    fn new(screenshot: Screenshot) -> Self {
        let offset = (
            screenshot.region.x - screenshot.output.rect.x,
            screenshot.region.y - screenshot.output.rect.y,
        );
        let markings = Markings::new(screenshot.region.width, screenshot.region.height);
        Self {
            document: Document {
                screenshot,
                markings,
                offset,
            },
            viewer: None,
            hover: None,
            pressed: None,
            copy_state: CopyState::Idle,
            save_state: CopyState::Idle,
        }
    }
}

struct State {
    qh: QueueHandle<Self>,
    connection: Connection,
    compositor: CompositorState,
    layer_shell: LayerShell,
    viewporter: wp_viewporter::WpViewporter,
    relative_manager: Option<zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1>,
    relative_pointer: Option<zwp_relative_pointer_v1::ZwpRelativePointerV1>,
    drag_pointer: Option<Point>,
    registry: RegistryState,
    seats: SeatState,
    outputs: OutputState,
    shm: Shm,
    pool: SlotPool,
    pointer: Option<ThemedPointer>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    keyboard_surface: Option<wl_surface::WlSurface>,
    pins: PinStore<Card>,
    suspended: Vec<PinId>,
    drag: Option<(PinId, Drag)>,
    saving: Option<PinId>,
    save_cancel: Option<tokio::sync::oneshot::Sender<()>>,
    generation: u64,
    capturing: bool,
    capture_runner: Option<Runner>,
    pending_copies: usize,
    quitting: bool,
    exit: bool,
    sender: channel::Sender<WorkerMessage>,
}

fn monitor_info(info: &OutputInfo) -> Option<Monitor> {
    let name = info.name.clone()?;
    let position = info.logical_position.unwrap_or(info.location);
    let physical = info.modes.iter().find(|mode| mode.current)?.dimensions;
    let rotated = matches!(
        info.transform,
        wl_output::Transform::_90
            | wl_output::Transform::_270
            | wl_output::Transform::Flipped90
            | wl_output::Transform::Flipped270
    );
    let physical = if rotated {
        (physical.1, physical.0)
    } else {
        physical
    };
    let scale = info.scale_factor.max(1);
    let logical = info
        .logical_size
        .unwrap_or((physical.0 / scale, physical.1 / scale));
    let rect = Rect::new(
        position.0,
        position.1,
        logical.0.try_into().ok()?,
        logical.1.try_into().ok()?,
    )
    .ok()?;
    let scale = (physical.0 as f64 / logical.0 as f64)
        .max(physical.1 as f64 / logical.1 as f64)
        .clamp(0.5, 8.0);
    Some(Monitor { name, rect, scale })
}

impl State {
    fn card(&self, id: PinId) -> Option<&Card> {
        self.pins.get(id).map(|pin| &pin.value)
    }
    fn card_mut(&mut self, id: PinId) -> Option<&mut Card> {
        self.pins.get_mut(id).map(|pin| &mut pin.value)
    }

    fn monitors(&self) -> Vec<(wl_output::WlOutput, Monitor)> {
        self.outputs
            .outputs()
            .filter_map(|output| {
                let info = self.outputs.info(&output)?;
                Some((output, monitor_info(&info)?))
            })
            .collect()
    }

    fn new_layer(
        &self,
        output: &wl_output::WlOutput,
        rect: Rect,
        monitor: Rect,
        namespace: &str,
    ) -> NativeLayer {
        let surface = self.compositor.create_surface(&self.qh);
        let viewport = self.viewporter.get_viewport(&surface, &self.qh, ());
        let layer = self.layer_shell.create_layer_surface(
            &self.qh,
            surface,
            Layer::Overlay,
            Some(namespace),
            Some(output),
        );
        layer.set_anchor(Anchor::TOP | Anchor::LEFT);
        layer.set_size(rect.width, rect.height);
        layer.set_margin(rect.y - monitor.y, 0, 0, rect.x - monitor.x);
        // Anchor against physical output edges, ignoring panel reservations.
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::OnDemand);
        layer.commit();
        NativeLayer {
            layer,
            viewport,
            logical_size: (rect.width, rect.height),
            ready: false,
            waiting_frame: false,
            dirty: true,
        }
    }

    fn show_card(&mut self, id: PinId) -> Result<(), String> {
        let card = self.card(id).ok_or("截图已关闭")?;
        if card.viewer.is_some() {
            return Ok(());
        }
        let document = &card.document;
        let snapshot = &document.screenshot;
        let (output, monitor) = self
            .monitors()
            .into_iter()
            .find(|(_, monitor)| monitor.name == snapshot.output.name)
            .ok_or("截图所在的显示器已移除")?;
        let region = Rect::new(
            monitor.rect.x + document.offset.0,
            monitor.rect.y + document.offset.1,
            snapshot.region.width,
            snapshot.region.height,
        )?;
        if !monitor.rect.contains(region) {
            return Err("显示器布局变化后，截图区域已超出屏幕".into());
        }
        let image = self.new_layer(&output, region, monitor.rect, "pinmark-image");
        let toolbar = self.new_layer(
            &output,
            toolbar_rect(region, monitor.rect),
            monitor.rect,
            "pinmark-controls",
        );
        let card = self.card_mut(id).ok_or("截图已关闭")?;
        card.viewer = Some(Viewer {
            output,
            monitor: monitor.rect,
            region,
            image,
            toolbar,
        });
        card.hover = None;
        card.pressed = None;
        Ok(())
    }

    fn display_new(&mut self, screenshot: Screenshot) {
        self.exit = false;
        let id = self.pins.replace_unpinned(Card::new(screenshot));
        if let Err(error) = self.show_card(id) {
            self.report_error(&error);
            self.close_card(id);
        }
        eprintln!("Pinmark：矩形、箭头、复制、另存为、图钉、关闭。图钉亮起时保留此图；未选工具时左键拖动，右键撤销。");
    }

    fn handle_request(&mut self, request: Request) {
        if self.quitting
            || ((self.saving.is_some() || self.pending_copies > 0) && request != Request::Quit)
        {
            return;
        }
        match request {
            Request::Capture => self.start_capture(),
            Request::Demo if !self.capturing => self.show_demo(),
            Request::Demo => (),
            Request::Quit => self.quit(),
        }
    }

    fn start_capture(&mut self) {
        if self.capturing || self.quitting {
            return;
        }
        let monitors: Vec<_> = self
            .monitors()
            .into_iter()
            .map(|(_, monitor)| monitor)
            .collect();
        if monitors.is_empty() {
            self.report_error("无法获取显示器信息");
            self.exit_if_idle();
            return;
        }
        self.suspended.clear();
        let mut removed_viewer = false;
        // Pinned layers stay visible. Only temporary images follow the original
        // hide/replace behavior, and their documents survive canceled capture.
        for pin in self.pins.iter_mut().filter(|pin| !pin.pinned) {
            removed_viewer |= pin.value.viewer.take().is_some();
            pin.value.document.markings.draft = None;
            self.suspended.push(pin.id);
        }
        self.drag = None;
        self.drag_pointer = None;
        self.keyboard_surface = None;
        let _ = self.connection.flush();
        self.generation += 1;
        let generation = self.generation;
        self.capturing = true;
        self.exit = false;
        let runner = Runner::default();
        self.capture_runner = Some(runner.clone());
        let sender = self.sender.clone();
        thread::spawn(move || {
            let result = backend::capture(monitors, runner, removed_viewer);
            let _ = sender.send(WorkerMessage::Captured(generation, result));
        });
    }

    fn show_demo(&mut self) {
        let Some((_, monitor)) = self.monitors().into_iter().next() else {
            self.report_error("没有可用显示器");
            self.exit_if_idle();
            return;
        };
        self.drag = None;
        self.drag_pointer = None;
        let width = 360.min(monitor.rect.width);
        let height = 220.min(monitor.rect.height);
        let region = Rect::new(
            monitor.rect.x + ((monitor.rect.width - width) / 2) as i32,
            monitor.rect.y + ((monitor.rect.height - height) / 2) as i32,
            width,
            height,
        )
        .unwrap();
        let mut image = Pixmap::new(width, height).unwrap();
        for (index, pixel) in image.pixels_mut().iter_mut().enumerate() {
            let x = index % width as usize;
            let y = index / width as usize;
            let c = if (x / 20 + y / 20).is_multiple_of(2) {
                220
            } else {
                245
            };
            *pixel = tiny_skia::PremultipliedColorU8::from_rgba(c, c, c, 255).unwrap();
        }
        self.display_new(Screenshot {
            region,
            output: monitor,
            image: Arc::new(image),
        });
        self.exit_if_idle();
    }

    fn restore_suspended(&mut self) {
        for id in std::mem::take(&mut self.suspended) {
            if self.card(id).is_none() {
                continue;
            }
            if let Err(error) = self.show_card(id) {
                self.report_error(&error);
                self.close_card(id);
            }
        }
    }

    fn worker_message(&mut self, message: WorkerMessage) {
        match message {
            WorkerMessage::Captured(generation, result) => {
                self.capturing = false;
                self.capture_runner.take();
                if self.quitting || generation != self.generation {
                    self.exit_if_idle();
                    return;
                }
                match result {
                    Ok(screenshot) => {
                        self.suspended.clear();
                        self.display_new(screenshot);
                    }
                    Err(TaskError::Cancelled) => self.restore_suspended(),
                    Err(error) => {
                        self.report_error(&error.to_string());
                        self.restore_suspended();
                    }
                }
                self.exit_if_idle();
            }
            WorkerMessage::Copied(id, result) => {
                self.pending_copies = self.pending_copies.saturating_sub(1);
                match result {
                    // Closing one card never erases other pinned images. The
                    // process exits naturally only after the final card closes.
                    Ok(()) => self.close_card(id),
                    Err(error) => {
                        if let Some(card) = self.card_mut(id) {
                            card.copy_state = CopyState::Error;
                            self.report_error(&error.to_string());
                            self.request_draw(id, SurfaceKind::Toolbar);
                        }
                    }
                }
                self.exit_if_idle();
            }
            WorkerMessage::Saved(id, result) => {
                self.saving = None;
                self.save_cancel.take();
                if self.quitting || self.card(id).is_none() {
                    self.exit_if_idle();
                    return;
                }
                let status = match result {
                    Ok(Some(path)) => {
                        eprintln!("Pinmark：已保存 {}", path.display());
                        CopyState::Done
                    }
                    Ok(None) | Err(TaskError::Cancelled) => CopyState::Idle,
                    Err(error) => {
                        self.report_error(&error.to_string());
                        CopyState::Error
                    }
                };
                if let Err(error) = self.show_card(id) {
                    self.report_error(&error);
                    self.close_card(id);
                }
                if let Some(card) = self.card_mut(id) {
                    card.save_state = status;
                }
                self.request_draw(id, SurfaceKind::Toolbar);
                self.exit_if_idle();
            }
            WorkerMessage::Quit => self.quit(),
        }
    }

    fn copy(&mut self, id: PinId) {
        if self.saving.is_some() || self.capturing {
            return;
        }
        let Some(card) = self.card(id) else {
            return;
        };
        if card.copy_state == CopyState::Working {
            return;
        }
        let image = card.document.screenshot.image.clone();
        let mut markings = card.document.markings.clone();
        markings.draft = None;
        let sender = self.sender.clone();
        self.pending_copies += 1;
        self.card_mut(id).unwrap().copy_state = CopyState::Working;
        self.request_draw(id, SurfaceKind::Toolbar);
        thread::spawn(move || {
            let result = render::export_png(&image, &markings)
                .map_err(TaskError::Failed)
                .and_then(backend::copy_png);
            let _ = sender.send(WorkerMessage::Copied(id, result));
        });
    }

    fn save_as(&mut self, id: PinId) {
        if self.saving.is_some() || self.pending_copies > 0 || self.capturing || self.quitting {
            return;
        }
        let Some(card) = self.card(id) else {
            return;
        };
        let image = card.document.screenshot.image.clone();
        let mut markings = card.document.markings.clone();
        markings.draft = None;
        let sender = self.sender.clone();
        let (cancel, receiver) = tokio::sync::oneshot::channel();
        self.save_cancel = Some(cancel);
        self.saving = Some(id);
        let card = self.card_mut(id).unwrap();
        card.save_state = CopyState::Working;
        card.viewer.take();
        self.drag = None;
        self.drag_pointer = None;
        self.keyboard_surface = None;
        let _ = self.connection.flush();
        thread::spawn(move || {
            let result = save::save_as(&image, &markings, receiver);
            let _ = sender.send(WorkerMessage::Saved(id, result));
        });
    }

    fn toggle_pin(&mut self, id: PinId) {
        if let Some(pinned) = self.pins.toggle_pin(id) {
            eprintln!(
                "Pinmark：{}",
                if pinned {
                    "已固定，后续截图不会替换此图"
                } else {
                    "已取消固定，下次截图会替换此图"
                }
            );
            self.request_draw(id, SurfaceKind::Toolbar);
        }
    }

    fn move_pin(&mut self, id: PinId, region: Rect) {
        let Some(card) = self.card_mut(id) else {
            return;
        };
        let Some(viewer) = &mut card.viewer else {
            return;
        };
        if viewer.region == region {
            return;
        }
        viewer.region = region;
        card.document.offset = (region.x - viewer.monitor.x, region.y - viewer.monitor.y);
        viewer.image.layer.set_margin(
            region.y - viewer.monitor.y,
            0,
            0,
            region.x - viewer.monitor.x,
        );
        viewer.image.layer.commit();
        let toolbar = toolbar_rect(region, viewer.monitor);
        viewer.toolbar.layer.set_margin(
            toolbar.y - viewer.monitor.y,
            0,
            0,
            toolbar.x - viewer.monitor.x,
        );
        viewer.toolbar.layer.commit();
    }

    fn close_card(&mut self, id: PinId) {
        if self.drag.is_some_and(|(drag_id, _)| drag_id == id) {
            self.drag = None;
            self.drag_pointer = None;
        }
        if self
            .keyboard_surface
            .as_ref()
            .and_then(|surface| self.surface_key(surface))
            .is_some_and(|(key, _)| key == id)
        {
            self.keyboard_surface = None;
        }
        self.pins.remove(id);
        self.exit_if_idle();
    }

    fn quit(&mut self) {
        self.quitting = true;
        self.drag = None;
        self.drag_pointer = None;
        self.suspended.clear();
        if let Some(cancel) = self.save_cancel.take() {
            let _ = cancel.send(());
        }
        self.pins.clear();
        self.keyboard_surface = None;
        if let Some(runner) = &self.capture_runner {
            runner.cancel();
        }
        self.exit_if_idle();
    }

    fn exit_if_idle(&mut self) {
        if self.pins.is_empty()
            && !self.capturing
            && self.saving.is_none()
            && self.pending_copies == 0
        {
            self.exit = true;
        }
    }

    fn report_error(&self, message: &str) {
        eprintln!("Pinmark：{message}");
        let message = message.to_owned();
        thread::spawn(move || {
            let _ = std::process::Command::new("notify-send")
                .args(["Pinmark", &message])
                .status();
        });
    }

    fn surface_key(&self, surface: &wl_surface::WlSurface) -> Option<(PinId, SurfaceKind)> {
        self.pins.iter().find_map(|pin| {
            let viewer = pin.value.viewer.as_ref()?;
            if viewer.image.layer.wl_surface() == surface {
                Some((pin.id, SurfaceKind::Image))
            } else if viewer.toolbar.layer.wl_surface() == surface {
                Some((pin.id, SurfaceKind::Toolbar))
            } else {
                None
            }
        })
    }

    fn layer_mut(&mut self, id: PinId, kind: SurfaceKind) -> Option<&mut NativeLayer> {
        let viewer = self.card_mut(id)?.viewer.as_mut()?;
        Some(match kind {
            SurfaceKind::Image => &mut viewer.image,
            SurfaceKind::Toolbar => &mut viewer.toolbar,
        })
    }

    fn request_draw(&mut self, id: PinId, kind: SurfaceKind) {
        let Some(layer) = self.layer_mut(id, kind) else {
            return;
        };
        layer.dirty = true;
        if layer.ready && !layer.waiting_frame {
            self.draw(id, kind);
        }
    }

    fn draw(&mut self, id: PinId, kind: SurfaceKind) {
        let Some(pin) = self.pins.get(id) else {
            return;
        };
        let card = &pin.value;
        let document = &card.document;
        let pixels = match kind {
            SurfaceKind::Image => {
                render::render_preview(&document.screenshot.image, &document.markings)
            }
            SurfaceKind::Toolbar => render::render_toolbar(
                document.markings.tool,
                card.hover,
                card.pressed,
                card.copy_state,
                card.save_state,
                pin.pinned,
                document.screenshot.image.width() as f32 / document.markings.width as f32,
            ),
        };
        let Some(viewer) = self
            .pins
            .get_mut(id)
            .and_then(|pin| pin.value.viewer.as_mut())
        else {
            return;
        };
        let layer = match kind {
            SurfaceKind::Image => &mut viewer.image,
            SurfaceKind::Toolbar => &mut viewer.toolbar,
        };
        let (buffer, bytes) = match self.pool.create_buffer(
            pixels.width() as i32,
            pixels.height() as i32,
            pixels.width() as i32 * 4,
            wl_shm::Format::Argb8888,
        ) {
            Ok(result) => result,
            Err(error) => {
                self.report_error(&error.to_string());
                return;
            }
        };
        if let Err(error) = render::write_argb(&pixels, bytes) {
            self.report_error(&error);
            return;
        }
        let surface = layer.layer.wl_surface();
        surface.set_buffer_scale(1);
        layer
            .viewport
            .set_destination(layer.logical_size.0 as i32, layer.logical_size.1 as i32);
        surface.damage_buffer(0, 0, pixels.width() as i32, pixels.height() as i32);
        surface.frame(&self.qh, surface.clone());
        if let Err(error) = buffer.attach_to(surface) {
            self.report_error(&error.to_string());
            return;
        }
        layer.layer.commit();
        layer.waiting_frame = true;
        layer.dirty = false;
    }
}

pub fn run(instance: &ipc::Instance, initial: Request) -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect_to_env()?;
    let (globals, mut queue) = registry_queue_init::<State>(&connection)?;
    let qh = queue.handle();
    let compositor = CompositorState::bind(&globals, &qh)?;
    let layer_version = globals.contents().with_list(|list| {
        list.iter()
            .find(|global| global.interface == "zwlr_layer_shell_v1")
            .map(|global| global.version)
            .unwrap_or(0)
    });
    if layer_version < 4 {
        return Err("需要支持 layer-shell v4 的 Wayland 合成器".into());
    }
    let layer_shell = LayerShell::bind(&globals, &qh)?;
    let viewporter = globals.bind::<wp_viewporter::WpViewporter, _, _>(&qh, 1..=1, ())?;
    let relative_manager = globals
        .bind::<zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1, _, _>(&qh, 1..=1, ())
        .ok();
    let shm = Shm::bind(&globals, &qh)?;
    let pool = SlotPool::new(1024 * 1024, &shm)?;
    let (sender, receiver) = channel::channel();
    let mut state = State {
        qh: qh.clone(),
        connection: connection.clone(),
        compositor,
        layer_shell,
        viewporter,
        relative_manager,
        relative_pointer: None,
        drag_pointer: None,
        registry: RegistryState::new(&globals),
        seats: SeatState::new(&globals, &qh),
        outputs: OutputState::new(&globals, &qh),
        shm,
        pool,
        pointer: None,
        keyboard: None,
        keyboard_surface: None,
        pins: PinStore::default(),
        suspended: Vec::new(),
        drag: None,
        saving: None,
        save_cancel: None,
        generation: 0,
        capturing: false,
        capture_runner: None,
        pending_copies: 0,
        quitting: false,
        exit: false,
        sender: sender.clone(),
    };
    queue.roundtrip(&mut state)?;
    queue.roundtrip(&mut state)?;
    let mut event_loop = EventLoop::<State>::try_new()?;
    let handle = event_loop.handle();
    WaylandSource::new(connection, queue).insert(handle.clone())?;
    handle.insert_source(receiver, |event, _, state| {
        if let channel::Event::Msg(message) = event {
            state.worker_message(message);
        }
    })?;
    let listener: UnixListener = instance.listener.try_clone()?;
    handle.insert_source(
        Generic::new(listener, Interest::READ, Mode::Level),
        |_, listener, state| {
            loop {
                match listener.accept() {
                    Ok((stream, _)) => match ipc::read_request(stream) {
                        Ok(request) => state.handle_request(request),
                        Err(error) => state.report_error(&error),
                    },
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                    Err(error) => {
                        state.report_error(&error.to_string());
                        break;
                    }
                }
            }
            Ok(PostAction::Continue)
        },
    )?;
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
    ])?;
    let signal_handle = signals.handle();
    thread::spawn(move || {
        if signals.forever().next().is_some() {
            let _ = sender.send(WorkerMessage::Quit);
        }
    });
    state.handle_request(initial);
    let result = if !state.exit {
        let stop = event_loop.get_signal();
        event_loop.run(None, &mut state, |state| {
            if state.exit {
                stop.stop();
            }
        })
    } else {
        Ok(())
    };
    signal_handle.close();
    if let Some(runner) = &state.capture_runner {
        runner.cancel();
    }
    result?;
    Ok(())
}

impl CompositorHandler for State {
    fn scale_factor_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: i32,
    ) {
    }
    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }
    fn surface_enter(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
    fn surface_leave(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
    fn frame(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        surface: &wl_surface::WlSurface,
        _: u32,
    ) {
        if let Some((id, kind)) = self.surface_key(surface) {
            if let Some(layer) = self.layer_mut(id, kind) {
                layer.waiting_frame = false;
                if layer.dirty {
                    self.draw(id, kind);
                }
            }
        }
    }
}
impl LayerShellHandler for State {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        if let Some((id, _)) = self.surface_key(layer.wl_surface()) {
            self.close_card(id);
        }
    }
    fn configure(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        layer: &LayerSurface,
        _: LayerSurfaceConfigure,
        _: u32,
    ) {
        if let Some((id, kind)) = self.surface_key(layer.wl_surface()) {
            if let Some(layer) = self.layer_mut(id, kind) {
                layer.ready = true;
            }
            self.request_draw(id, kind);
        }
    }
}
impl OutputHandler for State {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }
    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn output_destroyed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        output: wl_output::WlOutput,
    ) {
        let ids: Vec<_> = self
            .pins
            .iter()
            .filter(|pin| {
                pin.value
                    .viewer
                    .as_ref()
                    .is_some_and(|viewer| viewer.output == output)
            })
            .map(|pin| pin.id)
            .collect();
        for id in ids {
            self.close_card(id);
        }
    }
}
impl ShmHandler for State {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}
impl SeatHandler for State {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }
    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
    fn new_capability(
        &mut self,
        _: &Connection,
        qh: &QueueHandle<Self>,
        seat: wl_seat::WlSeat,
        capability: Capability,
    ) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            let surface = self.compositor.create_surface(qh);
            match self.seats.get_pointer_with_theme(
                qh,
                &seat,
                self.shm.wl_shm(),
                surface,
                ThemeSpec::System,
            ) {
                Ok(pointer) => {
                    if let Some(manager) = &self.relative_manager {
                        self.relative_pointer =
                            Some(manager.get_relative_pointer(pointer.pointer(), qh, ()));
                    }
                    self.pointer = Some(pointer);
                }
                Err(error) => self.report_error(&error.to_string()),
            }
        }
        if capability == Capability::Keyboard && self.keyboard.is_none() {
            self.keyboard = Some(seat.get_keyboard(qh, ()));
        }
    }
    fn remove_capability(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: wl_seat::WlSeat,
        capability: Capability,
    ) {
        if capability == Capability::Pointer {
            if let Some(relative) = self.relative_pointer.take() {
                relative.destroy();
            }
            self.pointer.take();
            self.drag = None;
            self.drag_pointer = None;
        }
        if capability == Capability::Keyboard {
            if let Some(keyboard) = self.keyboard.take() {
                keyboard.release();
            }
            self.keyboard_surface = None;
        }
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

impl PointerHandler for State {
    fn pointer_frame(
        &mut self,
        conn: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_pointer::WlPointer,
        events: &[PointerEvent],
    ) {
        use PointerEventKind::*;
        let origins: HashMap<_, _> = self
            .pins
            .iter()
            .filter_map(|pin| Some((pin.id, pin.value.viewer.as_ref()?.region)))
            .collect();
        let mut drag_motion = None;
        let mut drag_release = false;
        for event in events {
            let Some((id, kind)) = self.surface_key(&event.surface) else {
                continue;
            };
            let point = Point::new(event.position.0 as f32, event.position.1 as f32);
            match kind {
                SurfaceKind::Image => {
                    let tool = self
                        .card(id)
                        .map(|card| card.document.markings.tool)
                        .unwrap_or(Tool::Move);
                    if let Enter { .. } = event.kind {
                        if let Some(pointer) = &self.pointer {
                            let _ = pointer.set_cursor(
                                conn,
                                if tool == Tool::Move {
                                    CursorIcon::Grab
                                } else {
                                    CursorIcon::Crosshair
                                },
                            );
                        }
                    }
                    let origin = origins.get(&id).copied();
                    let global = origin.map(|region| {
                        Point::new(region.x as f32 + point.x, region.y as f32 + point.y)
                    });
                    match event.kind {
                        Press { button: 272, .. } if tool == Tool::Move => {
                            if let (Some(origin), Some(pointer)) = (origin, global) {
                                self.drag = Some((id, Drag { origin, pointer }));
                                self.drag_pointer = Some(pointer);
                                if let Some(pointer) = &self.pointer {
                                    let _ = pointer.set_cursor(conn, CursorIcon::Grabbing);
                                }
                            }
                        }
                        Motion { .. } if tool == Tool::Move => {
                            if self.drag.is_some_and(|(key, _)| key == id)
                                && self.relative_pointer.is_none()
                            {
                                drag_motion = global;
                            }
                        }
                        Release { button: 272, .. } if tool == Tool::Move => {
                            if self.drag.is_some_and(|(key, _)| key == id) {
                                if self.relative_pointer.is_none() {
                                    drag_motion = global;
                                }
                                drag_release = true;
                            }
                        }
                        Press { button: 272, .. } => {
                            if let Some(card) = self.card_mut(id) {
                                card.document.markings.begin(point);
                            }
                            self.request_draw(id, SurfaceKind::Image);
                        }
                        Motion { .. } => {
                            if let Some(card) = self.card_mut(id) {
                                if card.document.markings.draft.is_none() {
                                    continue;
                                }
                                card.document.markings.update(point);
                            }
                            self.request_draw(id, SurfaceKind::Image);
                        }
                        Release { button: 272, .. } => {
                            if let Some(card) = self.card_mut(id) {
                                card.document.markings.finish(point);
                            }
                            self.request_draw(id, SurfaceKind::Image);
                        }
                        Press { button: 273, .. } => {
                            if let Some(card) = self.card_mut(id) {
                                card.document.markings.undo();
                            }
                            self.request_draw(id, SurfaceKind::Image);
                        }
                        _ => (),
                    }
                }
                SurfaceKind::Toolbar => {
                    if let Enter { .. } = event.kind {
                        if let Some(pointer) = &self.pointer {
                            let _ = pointer.set_cursor(conn, CursorIcon::Default);
                        }
                    }
                    let Some(card) = self.card_mut(id) else {
                        continue;
                    };
                    let size = card.viewer.as_ref().unwrap().toolbar.logical_size;
                    let point = Point::new(
                        point.x * TOOLBAR_WIDTH as f32 / size.0 as f32,
                        point.y * TOOLBAR_HEIGHT as f32 / size.1 as f32,
                    );
                    card.hover = if matches!(event.kind, Leave { .. }) {
                        None
                    } else {
                        render::button_at(point)
                    };
                    let action = match event.kind {
                        Press { button: 272, .. } => {
                            card.pressed = card.hover;
                            None
                        }
                        Release { button: 272, .. } => card
                            .pressed
                            .take()
                            .filter(|button| Some(*button) == card.hover),
                        _ => None,
                    };
                    match action {
                        Some(Button::Rectangle) => {
                            self.drag = None;
                            if let Some(card) = self.card_mut(id) {
                                card.document.markings.select_tool(Tool::Rectangle);
                            }
                        }
                        Some(Button::Arrow) => {
                            self.drag = None;
                            if let Some(card) = self.card_mut(id) {
                                card.document.markings.select_tool(Tool::Arrow);
                            }
                        }
                        Some(Button::Copy) => self.copy(id),
                        Some(Button::Save) => self.save_as(id),
                        Some(Button::Pin) => self.toggle_pin(id),
                        Some(Button::Close) => self.close_card(id),
                        _ => (),
                    }
                    self.request_draw(id, SurfaceKind::Toolbar);
                }
            }
        }
        if let (Some((id, drag)), Some(pointer)) = (self.drag, drag_motion) {
            if let Some(viewer) = self.card(id).and_then(|card| card.viewer.as_ref()) {
                let region = drag.position(pointer, viewer.monitor);
                self.move_pin(id, region);
            }
        }
        if drag_release {
            self.drag = None;
            self.drag_pointer = None;
            if let Some(pointer) = &self.pointer {
                let _ = pointer.set_cursor(conn, CursorIcon::Grab);
            }
        }
    }
}

impl Dispatch<zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1,
        _: zwp_relative_pointer_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<zwp_relative_pointer_v1::ZwpRelativePointerV1, ()> for State {
    fn event(
        state: &mut Self,
        _: &zwp_relative_pointer_v1::ZwpRelativePointerV1,
        event: zwp_relative_pointer_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        let (dx, dy) = match event {
            zwp_relative_pointer_v1::Event::RelativeMotion { dx, dy, .. } => (dx, dy),
            _ => return,
        };
        if let (Some((id, drag)), Some(pointer)) = (state.drag, state.drag_pointer) {
            if let Some(viewer) = state.card(id).and_then(|card| card.viewer.as_ref()) {
                let pointer = Point::new(
                    (pointer.x + dx as f32)
                        .clamp(viewer.monitor.x as f32, viewer.monitor.right() as f32),
                    (pointer.y + dy as f32)
                        .clamp(viewer.monitor.y as f32, viewer.monitor.bottom() as f32),
                );
                let region = drag.position(pointer, viewer.monitor);
                state.drag_pointer = Some(pointer);
                state.move_pin(id, region);
            }
        }
    }
}
impl Dispatch<wl_keyboard::WlKeyboard, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_keyboard::WlKeyboard,
        event: wl_keyboard::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            wl_keyboard::Event::Enter { surface, .. } => state.keyboard_surface = Some(surface),
            wl_keyboard::Event::Leave { .. } => state.keyboard_surface = None,
            wl_keyboard::Event::Key {
                key: 1,
                state: WEnum::Value(wl_keyboard::KeyState::Pressed),
                ..
            } => {
                if let Some((id, _)) = state
                    .keyboard_surface
                    .as_ref()
                    .and_then(|surface| state.surface_key(surface))
                {
                    state.close_card(id);
                }
            }
            _ => (),
        }
    }
}
impl Dispatch<wp_viewporter::WpViewporter, ()> for State {
    fn event(
        _: &mut Self,
        _: &wp_viewporter::WpViewporter,
        _: wp_viewporter::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<wp_viewport::WpViewport, ()> for State {
    fn event(
        _: &mut Self,
        _: &wp_viewport::WpViewport,
        _: wp_viewport::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

delegate_compositor!(State);
delegate_output!(State);
delegate_shm!(State);
delegate_seat!(State);
delegate_pointer!(State);
delegate_layer!(State);
delegate_registry!(State);
impl ProvidesRegistryState for State {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}

#[derive(Default)]
struct CheckState {
    globals: Vec<(String, u32)>,
}
impl Dispatch<wl_registry::WlRegistry, ()> for CheckState {
    fn event(
        state: &mut Self,
        _: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            interface, version, ..
        } = event
        {
            state.globals.push((interface, version));
        }
    }
}
pub fn check_protocols() -> Result<Vec<(String, u32)>, Box<dyn std::error::Error>> {
    let connection = Connection::connect_to_env()?;
    let mut queue = connection.new_event_queue::<CheckState>();
    let _registry = connection.display().get_registry(&queue.handle(), ());
    let mut state = CheckState::default();
    queue.roundtrip(&mut state)?;
    Ok(state.globals)
}
