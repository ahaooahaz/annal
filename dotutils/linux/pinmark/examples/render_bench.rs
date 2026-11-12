use pinmark::{
    geometry::{Markings, Point, Tool},
    render::{export_png, render_document},
};
use std::time::Instant;
use tiny_skia::{Pixmap, PremultipliedColorU8};

fn main() {
    let mut image = Pixmap::new(1920, 1080).unwrap();
    for (index, pixel) in image.pixels_mut().iter_mut().enumerate() {
        let x = index % 1920;
        let y = index / 1920;
        *pixel =
            PremultipliedColorU8::from_rgba((x % 256) as u8, (y % 256) as u8, 120, 255).unwrap();
    }
    let mut markings = Markings::new(1920, 1080);
    markings.select_tool(Tool::Rectangle);
    markings.begin(Point::new(100.0, 100.0));
    markings.finish(Point::new(600.0, 400.0));
    markings.tool = Tool::Arrow;
    markings.begin(Point::new(800.0, 500.0));
    markings.finish(Point::new(1300.0, 700.0));
    let count = 30;
    let started = Instant::now();
    for _ in 0..count {
        std::hint::black_box(render_document(&image, &markings, true));
    }
    println!(
        "1920x1080 synthetic preview: {:.2} ms/frame",
        started.elapsed().as_secs_f64() * 1000.0 / count as f64
    );
    let started = Instant::now();
    let mut bytes = 0;
    for _ in 0..count {
        bytes = std::hint::black_box(export_png(&image, &markings).unwrap()).len();
    }
    println!(
        "1920x1080 synthetic export: {:.2} ms/image; {bytes} PNG bytes",
        started.elapsed().as_secs_f64() * 1000.0 / count as f64
    );
    println!("Synthetic image only: this does not capture a screen or change the clipboard.");
}
