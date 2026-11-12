use std::{io, os::unix::net::UnixListener, path::PathBuf, sync::Arc, thread};

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
    geometry::{
        copy_should_close, toolbar_rect, Drag, Markings, Point, Rect, Tool, TOOLBAR_HEIGHT,
        TOOLBAR_WIDTH,
    },
    ipc::{self, Request},
    render::{self, Button, CopyState},
    save,
};

#[derive(Debug)]
enum WorkerMessage {
    Captured(u64, Result<Screenshot, TaskError>),
    Copied(u64, Result<(), TaskError>),
    Saved(u64, Result<Option<PathBuf>, TaskError>),
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
        // LayerSurface then destroys its role before its wl_surface.
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
    viewer: Option<Viewer>,
    document: Option<Document>,
    hover: Option<Button>,
    pressed: Option<Button>,
    copy_state: CopyState,
    save_state: CopyState,
    drag: Option<Drag>,
    saving: bool,
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
    let integer_scale = info.scale_factor.max(1);
    let logical = info
        .logical_size
        .unwrap_or((physical.0 / integer_scale, physical.1 / integer_scale));
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
        // Zero would let bars/panels shift the surface. -1 anchors to physical
        // output edges and preserves the selected screenshot's exact position.
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

    fn show_document(&mut self) -> Result<(), String> {
        let document = self.document.as_ref().ok_or("没有截图")?;
        let snapshot = &document.screenshot;
        let (output, monitor) = self
            .monitors()
            .into_iter()
            .find(|(_, output)| output.name == snapshot.output.name)
            .ok_or("截图所在的显示器已移除")?;
        // Store offsets relative to the output so a moved pin survives save
        // dialogs, canceled captures, and changes to monitor layout.
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
        self.viewer = Some(Viewer {
            output,
            monitor: monitor.rect,
            region,
            image,
            toolbar,
        });
        self.hover = None;
        self.pressed = None;
        self.drag = None;
        self.copy_state = CopyState::Idle;
        self.save_state = CopyState::Idle;
        eprintln!(
            "Pinmark：工具栏为矩形、箭头、复制、另存为、关闭。未选工具时左键拖动；再次点击工具取消选中。右键撤销，Esc 关闭。"
        );
        Ok(())
    }

    fn handle_request(&mut self, request: Request) {
        if self.quitting || ((self.saving || self.pending_copies > 0) && request != Request::Quit) {
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
        let replacing_pin = self.viewer.take().is_some();
        if let Some(document) = &mut self.document {
            document.markings.draft = None;
        }
        self.keyboard_surface = None;
        let _ = self.connection.flush();
        self.generation += 1;
        let generation = self.generation;
        self.capturing = true;
        let runner = Runner::default();
        self.capture_runner = Some(runner.clone());
        let sender = self.sender.clone();
        thread::spawn(move || {
            let result = backend::capture(monitors, runner, replacing_pin);
            let _ = sender.send(WorkerMessage::Captured(generation, result));
        });
    }

    fn show_demo(&mut self) {
        let Some((_, monitor)) = self.monitors().into_iter().next() else {
            self.report_error("没有可用显示器");
            self.exit_if_idle();
            return;
        };
        self.viewer.take();
        self.generation += 1;
        let width = 360.min(monitor.rect.width);
        let height = 220.min(monitor.rect.height);
        let x = monitor.rect.x + ((monitor.rect.width - width) / 2) as i32;
        let y = monitor.rect.y + ((monitor.rect.height - height) / 2) as i32;
        let region = Rect::new(x, y, width, height).unwrap();
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
        self.document = Some(Document {
            offset: (region.x - monitor.rect.x, region.y - monitor.rect.y),
            screenshot: Screenshot {
                region,
                output: monitor,
                image: Arc::new(image),
            },
            markings: Markings::new(width, height),
        });
        if let Err(error) = self.show_document() {
            self.report_error(&error);
            self.document.take();
            self.exit_if_idle();
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
                        self.document = Some(Document {
                            offset: (
                                screenshot.region.x - screenshot.output.rect.x,
                                screenshot.region.y - screenshot.output.rect.y,
                            ),
                            markings: Markings::new(
                                screenshot.region.width,
                                screenshot.region.height,
                            ),
                            screenshot,
                        });
                    }
                    Err(TaskError::Cancelled) => (),
                    Err(error) => self.report_error(&error.to_string()),
                }
                if self.document.is_some() {
                    if let Err(error) = self.show_document() {
                        self.report_error(&error);
                        self.document.take();
                    }
                }
                self.exit_if_idle();
            }
            WorkerMessage::Copied(generation, result) => {
                self.pending_copies = self.pending_copies.saturating_sub(1);
                if self.viewer.is_some()
                    && copy_should_close(generation, self.generation, result.is_ok())
                {
                    // wl-copy has already become the background clipboard owner.
                    // Closing these surfaces cannot erase the copied PNG.
                    self.quit();
                    return;
                }
                if generation == self.generation && self.viewer.is_some() {
                    if let Err(error) = result {
                        self.report_error(&error.to_string());
                        self.copy_state = CopyState::Error;
                        self.request_draw(SurfaceKind::Toolbar);
                    }
                }
                self.exit_if_idle();
            }
            WorkerMessage::Saved(generation, result) => {
                self.saving = false;
                self.save_cancel.take();
                if self.quitting || generation != self.generation {
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
                if let Err(error) = self.show_document() {
                    self.report_error(&error);
                    self.document.take();
                }
                self.save_state = status;
                self.request_draw(SurfaceKind::Toolbar);
                self.exit_if_idle();
            }
            WorkerMessage::Quit => self.quit(),
        }
    }

    fn copy(&mut self) {
        if self.copy_state == CopyState::Working || self.saving {
            return;
        }
        let Some(document) = self.document.as_ref() else {
            return;
        };
        let image = document.screenshot.image.clone();
        let mut markings = document.markings.clone();
        markings.draft = None;
        let generation = self.generation;
        let sender = self.sender.clone();
        self.pending_copies += 1;
        self.copy_state = CopyState::Working;
        self.request_draw(SurfaceKind::Toolbar);
        thread::spawn(move || {
            let result = render::export_png(&image, &markings)
                .map_err(TaskError::Failed)
                .and_then(backend::copy_png);
            let _ = sender.send(WorkerMessage::Copied(generation, result));
        });
    }

    fn save_as(&mut self) {
        if self.saving || self.pending_copies > 0 || self.quitting {
            return;
        }
        let Some(document) = &self.document else {
            return;
        };
        let image = document.screenshot.image.clone();
        let mut markings = document.markings.clone();
        markings.draft = None;
        let generation = self.generation;
        let sender = self.sender.clone();
        let (cancel, receiver) = tokio::sync::oneshot::channel();
        self.save_cancel = Some(cancel);
        self.saving = true;
        self.save_state = CopyState::Working;
        self.drag = None;
        self.viewer.take();
        self.keyboard_surface = None;
        let _ = self.connection.flush();
        thread::spawn(move || {
            let result = save::save_as(&image, &markings, receiver);
            let _ = sender.send(WorkerMessage::Saved(generation, result));
        });
    }

    fn move_pin(&mut self, region: Rect) {
        let Some(viewer) = &mut self.viewer else {
            return;
        };
        if viewer.region == region {
            return;
        }
        viewer.region = region;
        if let Some(document) = &mut self.document {
            document.offset = (region.x - viewer.monitor.x, region.y - viewer.monitor.y);
        }
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

    fn quit(&mut self) {
        self.quitting = true;
        self.drag = None;
        if let Some(cancel) = self.save_cancel.take() {
            let _ = cancel.send(());
        }
        self.viewer.take();
        self.document.take();
        self.keyboard_surface = None;
        if let Some(runner) = &self.capture_runner {
            runner.cancel();
        }
        self.exit_if_idle();
    }

    fn exit_if_idle(&mut self) {
        if self.viewer.is_none() && !self.capturing && !self.saving && self.pending_copies == 0 {
            self.exit = true;
        }
    }

    fn report_error(&self, message: &str) {
        eprintln!("Pinmark：{message}");
        // Optional notification helper. The program does not depend on it.
        let message = message.to_owned();
        thread::spawn(move || {
            let _ = std::process::Command::new("notify-send")
                .args(["Pinmark", &message])
                .status();
        });
    }

    fn surface_kind(&self, surface: &wl_surface::WlSurface) -> Option<SurfaceKind> {
        let viewer = self.viewer.as_ref()?;
        if viewer.image.layer.wl_surface() == surface {
            Some(SurfaceKind::Image)
        } else if viewer.toolbar.layer.wl_surface() == surface {
            Some(SurfaceKind::Toolbar)
        } else {
            None
        }
    }

    fn request_draw(&mut self, kind: SurfaceKind) {
        if let Some(viewer) = &mut self.viewer {
            let layer = match kind {
                SurfaceKind::Image => &mut viewer.image,
                SurfaceKind::Toolbar => &mut viewer.toolbar,
            };
            layer.dirty = true;
            if !layer.ready || layer.waiting_frame {
                return;
            }
        } else {
            return;
        }
        self.draw(kind);
    }

    fn draw(&mut self, kind: SurfaceKind) {
        let Some(document) = &self.document else {
            return;
        };
        let pixels = match kind {
            SurfaceKind::Image => {
                render::render_preview(&document.screenshot.image, &document.markings)
            }
            SurfaceKind::Toolbar => render::render_toolbar(
                document.markings.tool,
                self.hover,
                self.pressed,
                self.copy_state,
                self.save_state,
                document.screenshot.image.width() as f32 / document.markings.width as f32,
            ),
        };
        let Some(viewer) = &mut self.viewer else {
            return;
        };
        let layer = match kind {
            SurfaceKind::Image => &mut viewer.image,
            SurfaceKind::Toolbar => &mut viewer.toolbar,
        };
        let result = self.pool.create_buffer(
            pixels.width() as i32,
            pixels.height() as i32,
            pixels.width() as i32 * 4,
            wl_shm::Format::Argb8888,
        );
        let (buffer, bytes) = match result {
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
        viewer: None,
        document: None,
        hover: None,
        pressed: None,
        copy_state: CopyState::Idle,
        save_state: CopyState::Idle,
        drag: None,
        saving: false,
        save_cancel: None,
        generation: 0,
        capturing: false,
        capture_runner: None,
        pending_copies: 0,
        quitting: false,
        exit: false,
        sender: sender.clone(),
    };
    // Receive output logical positions/sizes before asking slurp for a region.
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
        if let Some(kind) = self.surface_kind(surface) {
            let viewer = self.viewer.as_mut().unwrap();
            let layer = match kind {
                SurfaceKind::Image => &mut viewer.image,
                SurfaceKind::Toolbar => &mut viewer.toolbar,
            };
            layer.waiting_frame = false;
            if layer.dirty {
                self.draw(kind);
            }
        }
    }
}

impl LayerShellHandler for State {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        if self.surface_kind(layer.wl_surface()).is_some() {
            self.quit();
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
        if let Some(kind) = self.surface_kind(layer.wl_surface()) {
            let viewer = self.viewer.as_mut().unwrap();
            let slot = match kind {
                SurfaceKind::Image => &mut viewer.image,
                SurfaceKind::Toolbar => &mut viewer.toolbar,
            };
            slot.ready = true;
            self.request_draw(kind);
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
        if self
            .viewer
            .as_ref()
            .is_some_and(|viewer| viewer.output == output)
        {
            self.quit();
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
        // All motion events in one input frame refer to the surface position at
        // the start of that frame. Coalesce a drag before committing its move.
        let frame_origin = self.viewer.as_ref().map(|viewer| viewer.region);
        let mut drag_pointer = None;
        let mut drag_release = false;
        for event in events {
            let Some(kind) = self.surface_kind(&event.surface) else {
                continue;
            };
            let point = Point::new(event.position.0 as f32, event.position.1 as f32);
            match kind {
                SurfaceKind::Image => {
                    let tool = self
                        .document
                        .as_ref()
                        .map(|doc| doc.markings.tool)
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
                    let global = frame_origin.map(|region| {
                        Point::new(region.x as f32 + point.x, region.y as f32 + point.y)
                    });
                    match event.kind {
                        Press { button: 272, .. } if tool == Tool::Move => {
                            if let (Some(origin), Some(pointer)) = (frame_origin, global) {
                                self.drag = Some(Drag { origin, pointer });
                                self.drag_pointer = Some(pointer);
                                if let Some(pointer) = &self.pointer {
                                    let _ = pointer.set_cursor(conn, CursorIcon::Grabbing);
                                }
                            }
                        }
                        Motion { .. } if tool == Tool::Move => {
                            if self.drag.is_some() && self.relative_pointer.is_none() {
                                drag_pointer = global;
                            }
                        }
                        Release { button: 272, .. } if tool == Tool::Move => {
                            if self.drag.is_some() {
                                if self.relative_pointer.is_none() {
                                    drag_pointer = global;
                                }
                                drag_release = true;
                            }
                        }
                        Press { button: 272, .. } => {
                            if let Some(doc) = &mut self.document {
                                doc.markings.begin(point);
                            }
                            self.request_draw(SurfaceKind::Image);
                        }
                        Motion { .. } => {
                            if let Some(doc) = &mut self.document {
                                if doc.markings.draft.is_none() {
                                    continue;
                                }
                                doc.markings.update(point);
                            }
                            self.request_draw(SurfaceKind::Image);
                        }
                        Release { button: 272, .. } => {
                            if let Some(doc) = &mut self.document {
                                doc.markings.finish(point);
                            }
                            self.request_draw(SurfaceKind::Image);
                        }
                        Press { button: 273, .. } => {
                            if let Some(doc) = &mut self.document {
                                doc.markings.undo();
                            }
                            self.request_draw(SurfaceKind::Image);
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
                    let size = self.viewer.as_ref().unwrap().toolbar.logical_size;
                    let point = Point::new(
                        point.x * TOOLBAR_WIDTH as f32 / size.0 as f32,
                        point.y * TOOLBAR_HEIGHT as f32 / size.1 as f32,
                    );
                    self.hover = if matches!(event.kind, Leave { .. }) {
                        None
                    } else {
                        render::button_at(point)
                    };
                    match event.kind {
                        Press { button: 272, .. } => self.pressed = self.hover,
                        Release { button: 272, .. } => {
                            let action = self
                                .pressed
                                .take()
                                .filter(|button| Some(*button) == self.hover);
                            match action {
                                Some(Button::Rectangle) => {
                                    self.drag = None;
                                    if let Some(doc) = &mut self.document {
                                        doc.markings.select_tool(Tool::Rectangle);
                                    }
                                }
                                Some(Button::Arrow) => {
                                    self.drag = None;
                                    if let Some(doc) = &mut self.document {
                                        doc.markings.select_tool(Tool::Arrow);
                                    }
                                }
                                Some(Button::Copy) => self.copy(),
                                Some(Button::Save) => self.save_as(),
                                Some(Button::Close) => self.quit(),
                                _ => (),
                            }
                        }
                        _ => (),
                    }
                    self.request_draw(SurfaceKind::Toolbar);
                }
            }
        }
        if let (Some(drag), Some(pointer), Some(viewer)) =
            (self.drag, drag_pointer, self.viewer.as_ref())
        {
            let region = drag.position(pointer, viewer.monitor);
            self.move_pin(region);
        }
        if drag_release {
            self.drag = None;
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
        if let (Some(drag), Some(pointer), Some(viewer)) =
            (state.drag, state.drag_pointer, state.viewer.as_ref())
        {
            // Relative deltas do not change when the layer moves underneath the
            // cursor. This avoids feedback/jitter from surface-local positions.
            let pointer = Point::new(
                (pointer.x + dx as f32)
                    .clamp(viewer.monitor.x as f32, viewer.monitor.right() as f32),
                (pointer.y + dy as f32)
                    .clamp(viewer.monitor.y as f32, viewer.monitor.bottom() as f32),
            );
            state.drag_pointer = Some(pointer);
            let region = drag.position(pointer, viewer.monitor);
            state.move_pin(region);
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
            // Only physical Escape is needed. No xkbcommon dependency or global key grab.
            wl_keyboard::Event::Key {
                key: 1,
                state: WEnum::Value(wl_keyboard::KeyState::Pressed),
                ..
            } if state
                .keyboard_surface
                .as_ref()
                .is_some_and(|surface| state.surface_kind(surface).is_some()) =>
            {
                state.quit()
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
