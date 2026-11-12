use tiny_skia::{
    Color, FillRule, LineCap, LineJoin, Paint, PathBuilder, Pixmap, Rect as SkiaRect, Stroke,
    Transform,
};

use crate::geometry::{
    arrow_geometry, Annotation, Markings, Point, Tool, TOOLBAR_HEIGHT, TOOLBAR_WIDTH,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Rectangle,
    Arrow,
    Copy,
    Save,
    Close,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CopyState {
    Idle,
    Working,
    Done,
    Error,
}

pub fn button_at(point: Point) -> Option<Button> {
    if !point.x.is_finite()
        || !point.y.is_finite()
        || !(4.0..36.0).contains(&point.y)
        || point.x < 8.0
        || point.x >= TOOLBAR_WIDTH as f32 - 8.0
        || (point.x - 8.0) % 50.0 >= 48.0
    {
        return None;
    }
    match ((point.x - 8.0) / 50.0) as usize {
        0 => Some(Button::Rectangle),
        1 => Some(Button::Arrow),
        2 => Some(Button::Copy),
        3 => Some(Button::Save),
        4 => Some(Button::Close),
        _ => None,
    }
}

pub fn decode_png(data: &[u8]) -> Result<Pixmap, String> {
    if data.len() < 24 || &data[..8] != b"\x89PNG\r\n\x1a\n" || &data[12..16] != b"IHDR" {
        return Err("截图没有返回有效的 PNG".into());
    }
    let width = u32::from_be_bytes(data[16..20].try_into().unwrap());
    let height = u32::from_be_bytes(data[20..24].try_into().unwrap());
    if width == 0 || height == 0 || u64::from(width) * u64::from(height) > 32_000_000 {
        return Err("截图像素尺寸无效或过大".into());
    }
    Pixmap::decode_png(data).map_err(|error| format!("无法解码截图：{error}"))
}

fn stroke() -> Stroke {
    Stroke {
        width: 3.0,
        line_cap: LineCap::Round,
        line_join: LineJoin::Round,
        ..Stroke::default()
    }
}

fn draw_mark(canvas: &mut Pixmap, mark: Annotation, transform: Transform) {
    if !mark.meaningful() {
        return;
    }
    let mut paint = Paint::default();
    paint.set_color_rgba8(239, 68, 68, 255);
    match mark.tool {
        Tool::Move => (),
        Tool::Rectangle => {
            let (left, top, right, bottom) = mark.bounds();
            if let Some(rect) = SkiaRect::from_ltrb(left, top, right, bottom) {
                let path = PathBuilder::from_rect(rect);
                canvas.stroke_path(&path, &paint, &stroke(), transform, None);
            }
        }
        Tool::Arrow => {
            if let Some(arrow) = arrow_geometry(mark) {
                let mut shaft = PathBuilder::new();
                shaft.move_to(arrow.tail.x, arrow.tail.y);
                shaft.line_to(arrow.base.x, arrow.base.y);
                if let Some(path) = shaft.finish() {
                    canvas.stroke_path(&path, &paint, &stroke(), transform, None);
                }
                let mut head = PathBuilder::new();
                head.move_to(arrow.tip.x, arrow.tip.y);
                head.line_to(arrow.left.x, arrow.left.y);
                head.line_to(arrow.right.x, arrow.right.y);
                head.close();
                if let Some(path) = head.finish() {
                    canvas.fill_path(&path, &paint, FillRule::Winding, transform, None);
                }
            }
        }
    }
}

pub fn render_document(image: &Pixmap, markings: &Markings, include_draft: bool) -> Pixmap {
    let mut canvas = image.clone();
    let transform = Transform::from_scale(
        image.width() as f32 / markings.width as f32,
        image.height() as f32 / markings.height as f32,
    );
    for mark in &markings.items {
        draw_mark(&mut canvas, *mark, transform);
    }
    if include_draft {
        if let Some(mark) = markings.draft {
            draw_mark(&mut canvas, mark, transform);
        }
    }
    canvas
}

pub fn render_preview(image: &Pixmap, markings: &Markings) -> Pixmap {
    let mut canvas = render_document(image, markings, true);
    let transform = Transform::from_scale(
        image.width() as f32 / markings.width as f32,
        image.height() as f32 / markings.height as f32,
    );
    // A dark inner keyline plus a bright cyan edge stays visible against both
    // light and dark screen content. This frame exists only in the preview.
    for (width, color) in [(3.0, (15, 23, 42)), (1.5, (56, 189, 248))] {
        let inset = width / 2.0;
        let mut paint = Paint::default();
        paint.set_color_rgba8(color.0, color.1, color.2, 255);
        if let Some(rect) = SkiaRect::from_ltrb(
            inset,
            inset,
            markings.width as f32 - inset,
            markings.height as f32 - inset,
        ) {
            canvas.stroke_path(
                &PathBuilder::from_rect(rect),
                &paint,
                &Stroke {
                    width,
                    ..Stroke::default()
                },
                transform,
                None,
            );
        } else {
            canvas.fill(Color::from_rgba8(56, 189, 248, 255));
        }
    }
    canvas
}

pub fn export_png(image: &Pixmap, markings: &Markings) -> Result<Vec<u8>, String> {
    let canvas = render_document(image, markings, false);
    let opaque = canvas.pixels().iter().all(|pixel| pixel.alpha() == 255);
    let mut pixels = Vec::with_capacity(
        canvas.width() as usize * canvas.height() as usize * if opaque { 3 } else { 4 },
    );
    for pixel in canvas.pixels() {
        let color = pixel.demultiply();
        pixels.extend_from_slice(&[color.red(), color.green(), color.blue()]);
        if !opaque {
            pixels.push(color.alpha());
        }
    }
    let mut data = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut data, canvas.width(), canvas.height());
        encoder.set_color(if opaque {
            png::ColorType::Rgb
        } else {
            png::ColorType::Rgba
        });
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_compression(png::Compression::Fast);
        encoder.set_filter(png::FilterType::Sub);
        let mut writer = encoder
            .write_header()
            .map_err(|error| format!("无法编码标注图片：{error}"))?;
        writer
            .write_image_data(&pixels)
            .map_err(|error| format!("无法编码标注图片：{error}"))?;
    }
    Ok(data)
}

fn icon_line(canvas: &mut Pixmap, points: &[(f32, f32)], paint: &Paint, transform: Transform) {
    let mut path = PathBuilder::new();
    if let Some(&(x, y)) = points.first() {
        path.move_to(x, y);
        for &(x, y) in &points[1..] {
            path.line_to(x, y);
        }
    }
    if let Some(path) = path.finish() {
        canvas.stroke_path(
            &path,
            paint,
            &Stroke {
                width: 2.0,
                line_cap: LineCap::Round,
                line_join: LineJoin::Round,
                ..Stroke::default()
            },
            transform,
            None,
        );
    }
}

pub fn render_toolbar(
    tool: Tool,
    hover: Option<Button>,
    pressed: Option<Button>,
    copy: CopyState,
    save: CopyState,
    scale: f32,
) -> Pixmap {
    let scale = scale.clamp(1.0, 4.0);
    let mut canvas = Pixmap::new(
        (TOOLBAR_WIDTH as f32 * scale).ceil() as u32,
        (TOOLBAR_HEIGHT as f32 * scale).ceil() as u32,
    )
    .unwrap();
    canvas.fill(Color::from_rgba8(17, 24, 39, 245));
    let transform = Transform::from_scale(scale, scale);
    let buttons = [
        Button::Rectangle,
        Button::Arrow,
        Button::Copy,
        Button::Save,
        Button::Close,
    ];
    for (index, button) in buttons.iter().enumerate() {
        let x = 8.0 + index as f32 * 50.0;
        let selected = matches!(
            (button, tool),
            (Button::Rectangle, Tool::Rectangle) | (Button::Arrow, Tool::Arrow)
        );
        let status = match button {
            Button::Copy => copy,
            Button::Save => save,
            _ => CopyState::Idle,
        };
        let background = if pressed == Some(*button) {
            (30, 64, 175)
        } else if status == CopyState::Done {
            (22, 101, 52)
        } else if status == CopyState::Error {
            (153, 27, 27)
        } else if selected {
            (37, 99, 235)
        } else if hover == Some(*button) {
            (55, 65, 81)
        } else {
            (31, 41, 55)
        };
        let mut bg = Paint::default();
        bg.set_color_rgba8(background.0, background.1, background.2, 255);
        canvas.fill_rect(
            SkiaRect::from_xywh(x, 4.0, 48.0, 32.0).unwrap(),
            &bg,
            transform,
            None,
        );
        let mut fg = Paint::default();
        fg.set_color_rgba8(241, 245, 249, 255);
        let cx = x + 24.0;
        match button {
            Button::Rectangle => icon_line(
                &mut canvas,
                &[
                    (cx - 9.0, 12.0),
                    (cx + 9.0, 12.0),
                    (cx + 9.0, 28.0),
                    (cx - 9.0, 28.0),
                    (cx - 9.0, 12.0),
                ],
                &fg,
                transform,
            ),
            Button::Arrow => {
                icon_line(
                    &mut canvas,
                    &[(cx - 9.0, 28.0), (cx + 9.0, 12.0)],
                    &fg,
                    transform,
                );
                icon_line(
                    &mut canvas,
                    &[(cx + 1.0, 12.0), (cx + 9.0, 12.0), (cx + 9.0, 20.0)],
                    &fg,
                    transform,
                );
            }
            Button::Copy if copy == CopyState::Done => icon_line(
                &mut canvas,
                &[(cx - 9.0, 20.0), (cx - 3.0, 26.0), (cx + 10.0, 13.0)],
                &fg,
                transform,
            ),
            Button::Copy if copy == CopyState::Working => icon_line(
                &mut canvas,
                &[
                    (cx - 8.0, 12.0),
                    (cx + 8.0, 12.0),
                    (cx - 8.0, 28.0),
                    (cx + 8.0, 28.0),
                ],
                &fg,
                transform,
            ),
            Button::Copy => {
                icon_line(
                    &mut canvas,
                    &[
                        (cx - 3.0, 14.0),
                        (cx - 3.0, 10.0),
                        (cx + 10.0, 10.0),
                        (cx + 10.0, 24.0),
                        (cx + 6.0, 24.0),
                    ],
                    &fg,
                    transform,
                );
                icon_line(
                    &mut canvas,
                    &[
                        (cx - 10.0, 16.0),
                        (cx + 3.0, 16.0),
                        (cx + 3.0, 30.0),
                        (cx - 10.0, 30.0),
                        (cx - 10.0, 16.0),
                    ],
                    &fg,
                    transform,
                );
            }
            Button::Save if save == CopyState::Done => icon_line(
                &mut canvas,
                &[(cx - 9.0, 20.0), (cx - 3.0, 26.0), (cx + 10.0, 13.0)],
                &fg,
                transform,
            ),
            Button::Save => {
                icon_line(
                    &mut canvas,
                    &[
                        (cx - 9.0, 10.0),
                        (cx + 7.0, 10.0),
                        (cx + 10.0, 13.0),
                        (cx + 10.0, 30.0),
                        (cx - 9.0, 30.0),
                        (cx - 9.0, 10.0),
                    ],
                    &fg,
                    transform,
                );
                icon_line(
                    &mut canvas,
                    &[
                        (cx - 4.0, 10.0),
                        (cx - 4.0, 17.0),
                        (cx + 4.0, 17.0),
                        (cx + 4.0, 10.0),
                    ],
                    &fg,
                    transform,
                );
                icon_line(
                    &mut canvas,
                    &[
                        (cx - 4.0, 29.0),
                        (cx - 4.0, 23.0),
                        (cx + 5.0, 23.0),
                        (cx + 5.0, 29.0),
                    ],
                    &fg,
                    transform,
                );
            }
            Button::Close => {
                icon_line(
                    &mut canvas,
                    &[(cx - 7.0, 13.0), (cx + 7.0, 27.0)],
                    &fg,
                    transform,
                );
                icon_line(
                    &mut canvas,
                    &[(cx + 7.0, 13.0), (cx - 7.0, 27.0)],
                    &fg,
                    transform,
                );
            }
        }
    }
    canvas
}

pub fn write_argb(canvas: &Pixmap, buffer: &mut [u8]) -> Result<(), String> {
    let required = canvas.data().len();
    if buffer.len() < required {
        return Err(format!(
            "共享绘图缓冲区过小：需要 {required} 字节，实际 {} 字节",
            buffer.len()
        ));
    }
    // SCTK slots round allocations up to 64 bytes. The returned slice can be
    // larger than stride * height; only its active pixel prefix is a canvas.
    for (rgba, argb) in canvas
        .data()
        .as_chunks::<4>()
        .0
        .iter()
        .zip(buffer[..required].as_chunks_mut::<4>().0.iter_mut())
    {
        let packed = (u32::from(rgba[3]) << 24)
            | (u32::from(rgba[0]) << 16)
            | (u32::from(rgba[1]) << 8)
            | u32::from(rgba[2]);
        argb.copy_from_slice(&packed.to_ne_bytes());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source() -> Pixmap {
        let mut image = Pixmap::new(200, 100).unwrap();
        image.fill(Color::from_rgba8(10, 20, 30, 255));
        image
    }

    #[test]
    fn export_preserves_resolution_and_unmarked_pixels() {
        let image = source();
        let mut marks = Markings::new(100, 50);
        marks.select_tool(Tool::Rectangle);
        marks.begin(Point::new(10.0, 10.0));
        marks.finish(Point::new(40.0, 30.0));
        let png = export_png(&image, &marks).unwrap();
        let result = decode_png(&png).unwrap();
        assert_eq!((result.width(), result.height()), (200, 100));
        assert_eq!(result.pixel(150, 80), image.pixel(150, 80));
        assert!(result.pixel(40, 20).unwrap().red() > 200);
    }

    #[test]
    fn draft_is_previewed_but_not_copied() {
        let image = source();
        let mut marks = Markings::new(100, 50);
        marks.select_tool(Tool::Rectangle);
        marks.begin(Point::new(10.0, 10.0));
        marks.update(Point::new(40.0, 30.0));
        assert_ne!(render_document(&image, &marks, true).data(), image.data());
        assert_eq!(render_document(&image, &marks, false).data(), image.data());
    }

    #[test]
    fn arrow_is_rendered_in_both_directions() {
        for (start, end) in [
            (Point::new(5.0, 25.0), Point::new(90.0, 25.0)),
            (Point::new(90.0, 25.0), Point::new(5.0, 25.0)),
        ] {
            let image = source();
            let mut marks = Markings::new(100, 50);
            marks.tool = Tool::Arrow;
            marks.begin(start);
            marks.finish(end);
            let result = render_document(&image, &marks, false);
            assert!(result.pixel(100, 50).unwrap().red() > 200);
        }
    }

    #[test]
    fn pixel_channels_match_wayland_argb() {
        let mut image = Pixmap::new(1, 1).unwrap();
        image.fill(Color::from_rgba8(255, 0, 0, 255));
        let mut buffer = [0; 4];
        write_argb(&image, &mut buffer).unwrap();
        assert_eq!(u32::from_ne_bytes(buffer), 0xffff0000);
        assert!(write_argb(&image, &mut []).is_err());
    }

    #[test]
    fn toolbar_hit_testing_and_hidpi() {
        assert_eq!(button_at(Point::new(20.0, 20.0)), Some(Button::Rectangle));
        assert_eq!(button_at(Point::new(120.0, 20.0)), Some(Button::Copy));
        assert_eq!(button_at(Point::new(200.0, 20.0)), Some(Button::Save));
        assert_eq!(button_at(Point::new(240.0, 20.0)), Some(Button::Close));
        assert!(button_at(Point::new(2.0, 20.0)).is_none());
        assert!(button_at(Point::new(56.5, 20.0)).is_none());
        assert!(button_at(Point::new(f32::NAN, 20.0)).is_none());
        let toolbar = render_toolbar(
            Tool::Arrow,
            None,
            None,
            CopyState::Idle,
            CopyState::Done,
            1.5,
        );
        assert_eq!((toolbar.width(), toolbar.height()), (399, 60));
    }

    #[test]
    fn padded_shm_slots_accept_odd_image_sizes_without_overwriting_padding() {
        for (width, height) in [(1, 1), (17, 3), (123, 77)] {
            let mut image = Pixmap::new(width, height).unwrap();
            image.fill(Color::from_rgba8(255, 0, 0, 255));
            let needed = image.data().len();
            let aligned = (needed + 63) & !63;
            let mut buffer = vec![0xaa; aligned];
            write_argb(&image, &mut buffer).unwrap();
            assert_eq!(
                u32::from_ne_bytes(buffer[..4].try_into().unwrap()),
                0xffff0000
            );
            assert!(buffer[needed..].iter().all(|byte| *byte == 0xaa));
            assert!(write_argb(&image, &mut buffer[..needed - 1]).is_err());
        }
    }

    #[test]
    fn prominent_preview_frame_never_changes_exported_image_or_geometry() {
        let image = source();
        let marks = Markings::new(100, 50);
        let preview = render_preview(&image, &marks);
        assert_eq!(
            (preview.width(), preview.height()),
            (image.width(), image.height())
        );
        assert_ne!(preview.pixel(0, 0), image.pixel(0, 0));
        assert_eq!(preview.pixel(100, 50), image.pixel(100, 50));
        let exported = decode_png(&export_png(&image, &marks).unwrap()).unwrap();
        assert_eq!(exported.data(), image.data());
        assert!(
            render_preview(&Pixmap::new(1, 1).unwrap(), &Markings::new(1, 1))
                .pixel(0, 0)
                .is_some()
        );
    }

    #[test]
    fn transparency_is_preserved_in_export() {
        let mut image = Pixmap::new(10, 10).unwrap();
        image.fill(Color::from_rgba8(100, 50, 20, 128));
        let marks = Markings::new(10, 10);
        let output = decode_png(&export_png(&image, &marks).unwrap()).unwrap();
        assert_eq!(output.pixel(5, 5).unwrap().alpha(), 128);
        assert_eq!(output.pixel(5, 5), image.pixel(5, 5));
    }

    #[test]
    fn malformed_images_are_rejected() {
        assert!(decode_png(b"not png").is_err());
        let mut bytes = vec![0; 24];
        bytes[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
        bytes[12..16].copy_from_slice(b"IHDR");
        bytes[16..20].copy_from_slice(&100_000_u32.to_be_bytes());
        bytes[20..24].copy_from_slice(&100_000_u32.to_be_bytes());
        assert!(decode_png(&bytes).is_err());
    }
}
