use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

impl Rect {
    pub fn new(x: i32, y: i32, width: u32, height: u32) -> Result<Self, String> {
        if width == 0 || height == 0 || width > 16_384 || height > 16_384 {
            return Err("截图区域尺寸无效或过大".into());
        }
        Ok(Self {
            x,
            y,
            width,
            height,
        })
    }

    pub fn right(self) -> i64 {
        i64::from(self.x) + i64::from(self.width)
    }

    pub fn bottom(self) -> i64 {
        i64::from(self.y) + i64::from(self.height)
    }

    pub fn contains(self, other: Self) -> bool {
        self.x <= other.x
            && self.y <= other.y
            && self.right() >= other.right()
            && self.bottom() >= other.bottom()
    }

    pub fn geometry(self) -> String {
        format!("{},{} {}x{}", self.x, self.y, self.width, self.height)
    }

    pub fn clamp_point(self, point: Point) -> Point {
        Point::new(
            point.x.clamp(0.0, self.width as f32),
            point.y.clamp(0.0, self.height as f32),
        )
    }
}

impl FromStr for Rect {
    type Err = String;

    fn from_str(text: &str) -> Result<Self, Self::Err> {
        let fields: Vec<_> = text.split_whitespace().collect();
        if fields.len() != 2 {
            return Err("无法解析框选区域".into());
        }
        let (x, y) = fields[0].split_once(',').ok_or("缺少区域坐标")?;
        let (width, height) = fields[1].split_once('x').ok_or("缺少区域尺寸")?;
        Self::new(
            x.parse().map_err(|_| "无效的 X 坐标")?,
            y.parse().map_err(|_| "无效的 Y 坐标")?,
            width.parse().map_err(|_| "无效的区域宽度")?,
            height.parse().map_err(|_| "无效的区域高度")?,
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tool {
    Move,
    Rectangle,
    Arrow,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Annotation {
    pub tool: Tool,
    pub start: Point,
    pub end: Point,
}

impl Annotation {
    pub fn bounds(self) -> (f32, f32, f32, f32) {
        (
            self.start.x.min(self.end.x),
            self.start.y.min(self.end.y),
            self.start.x.max(self.end.x),
            self.start.y.max(self.end.y),
        )
    }

    pub fn meaningful(self) -> bool {
        if ![self.start.x, self.start.y, self.end.x, self.end.y]
            .iter()
            .all(|n| n.is_finite())
        {
            return false;
        }
        match self.tool {
            Tool::Move => false,
            Tool::Rectangle => {
                let (left, top, right, bottom) = self.bounds();
                right - left >= 2.0 && bottom - top >= 2.0
            }
            Tool::Arrow => (self.end.x - self.start.x).hypot(self.end.y - self.start.y) >= 4.0,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Arrow {
    pub tail: Point,
    pub base: Point,
    pub tip: Point,
    pub left: Point,
    pub right: Point,
}

pub fn arrow_geometry(annotation: Annotation) -> Option<Arrow> {
    if !annotation.meaningful() {
        return None;
    }
    let dx = annotation.end.x - annotation.start.x;
    let dy = annotation.end.y - annotation.start.y;
    let length = dx.hypot(dy);
    let (ux, uy) = (dx / length, dy / length);
    let head_length = 12.0_f32.min(length * 0.55);
    let half_width = 5.1_f32.min(head_length * 0.6);
    let base = Point::new(
        annotation.end.x - ux * head_length,
        annotation.end.y - uy * head_length,
    );
    Some(Arrow {
        tail: annotation.start,
        base,
        tip: annotation.end,
        left: Point::new(base.x - uy * half_width, base.y + ux * half_width),
        right: Point::new(base.x + uy * half_width, base.y - ux * half_width),
    })
}

#[derive(Debug, Clone)]
pub struct Markings {
    pub width: u32,
    pub height: u32,
    pub tool: Tool,
    pub items: Vec<Annotation>,
    pub draft: Option<Annotation>,
}

impl Markings {
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            tool: Tool::Move,
            items: Vec::new(),
            draft: None,
        }
    }

    fn point(&self, point: Point) -> Point {
        Point::new(
            point.x.clamp(0.0, self.width as f32),
            point.y.clamp(0.0, self.height as f32),
        )
    }

    pub fn select_tool(&mut self, tool: Tool) {
        self.draft = None;
        self.tool = if self.tool == tool { Tool::Move } else { tool };
    }

    pub fn begin(&mut self, point: Point) {
        if self.tool == Tool::Move {
            return;
        }
        if !point.x.is_finite() || !point.y.is_finite() {
            return;
        }
        let point = self.point(point);
        self.draft = Some(Annotation {
            tool: self.tool,
            start: point,
            end: point,
        });
    }

    pub fn update(&mut self, point: Point) {
        if !point.x.is_finite() || !point.y.is_finite() {
            return;
        }
        let point = self.point(point);
        if let Some(draft) = &mut self.draft {
            draft.end = point;
        }
    }

    pub fn finish(&mut self, point: Point) {
        self.update(point);
        if let Some(draft) = self.draft.take() {
            if draft.meaningful() {
                self.items.push(draft);
            }
        }
    }

    pub fn undo(&mut self) {
        if self.draft.take().is_none() {
            self.items.pop();
        }
    }

    pub fn visible(&self) -> impl Iterator<Item = &Annotation> {
        self.items.iter().chain(self.draft.iter())
    }
}

pub const TOOLBAR_WIDTH: u32 = 316;
pub const TOOLBAR_HEIGHT: u32 = 40;

#[derive(Debug, Clone, Copy)]
pub struct Drag {
    pub origin: Rect,
    pub pointer: Point,
}

impl Drag {
    pub fn position(self, pointer: Point, monitor: Rect) -> Rect {
        if !pointer.x.is_finite() || !pointer.y.is_finite() {
            return self.origin;
        }
        let dx = (pointer.x - self.pointer.x).round() as i64;
        let dy = (pointer.y - self.pointer.y).round() as i64;
        let x = (i64::from(self.origin.x).saturating_add(dx)).clamp(
            i64::from(monitor.x),
            monitor
                .right()
                .saturating_sub(i64::from(self.origin.width))
                .max(i64::from(monitor.x)),
        );
        let y = (i64::from(self.origin.y).saturating_add(dy)).clamp(
            i64::from(monitor.y),
            monitor
                .bottom()
                .saturating_sub(i64::from(self.origin.height))
                .max(i64::from(monitor.y)),
        );
        Rect {
            x: x as i32,
            y: y as i32,
            ..self.origin
        }
    }
}

pub fn toolbar_rect(region: Rect, monitor: Rect) -> Rect {
    let width = TOOLBAR_WIDTH.min(monitor.width);
    let height = TOOLBAR_HEIGHT.min(monitor.height);
    let x = (region.right() - i64::from(width))
        .clamp(i64::from(monitor.x), monitor.right() - i64::from(width)) as i32;
    let y = if i64::from(region.y) - i64::from(height) - 8 >= i64::from(monitor.y) {
        region.y - height as i32 - 8
    } else if region.bottom() + 8 + i64::from(height) <= monitor.bottom() {
        (region.bottom() + 8) as i32
    } else {
        i64::from(region.y).clamp(i64::from(monitor.y), monitor.bottom() - i64::from(height)) as i32
    };
    Rect {
        x,
        y,
        width,
        height,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_negative_monitor_coordinates() {
        assert_eq!("-1920,10 200x100\n".parse::<Rect>().unwrap().x, -1920);
        assert!("0,0 0x100".parse::<Rect>().is_err());
        assert!("0,0 99999x100".parse::<Rect>().is_err());
        assert!("0,0 10x10 extra".parse::<Rect>().is_err());
        assert!("0,0 10x10;rm".parse::<Rect>().is_err());
    }

    #[test]
    fn bounds_do_not_overflow_at_large_coordinates() {
        let outer = Rect::new(i32::MAX - 50, 0, 100, 100).unwrap();
        let inner = Rect::new(i32::MAX - 10, 0, 50, 50).unwrap();
        assert!(outer.contains(inner));
    }

    #[test]
    fn reversed_rectangles_and_undo() {
        let mut marks = Markings::new(100, 80);
        marks.select_tool(Tool::Rectangle);
        marks.begin(Point::new(90.0, 70.0));
        marks.finish(Point::new(10.0, 20.0));
        assert_eq!(marks.items[0].bounds(), (10.0, 20.0, 90.0, 70.0));
        marks.begin(Point::new(20.0, 20.0));
        marks.undo();
        assert_eq!(marks.items.len(), 1);
        marks.undo();
        assert!(marks.items.is_empty());
    }

    #[test]
    fn clip_drag_to_image_and_drop_tiny_marks() {
        let mut marks = Markings::new(100, 80);
        marks.select_tool(Tool::Rectangle);
        marks.begin(Point::new(-10.0, -20.0));
        marks.finish(Point::new(200.0, 100.0));
        assert_eq!(marks.items[0].bounds(), (0.0, 0.0, 100.0, 80.0));
        marks.begin(Point::new(1.0, 1.0));
        marks.finish(Point::new(1.5, 1.5));
        assert_eq!(marks.items.len(), 1);
        marks.begin(Point::new(f32::NAN, 2.0));
        assert!(marks.draft.is_none());
    }

    #[test]
    fn arrow_tip_is_end_and_head_is_symmetric() {
        let mark = Annotation {
            tool: Tool::Arrow,
            start: Point::new(5.0, 15.0),
            end: Point::new(95.0, 15.0),
        };
        let arrow = arrow_geometry(mark).unwrap();
        assert_eq!(arrow.tip, mark.end);
        assert!(arrow.base.x < arrow.tip.x);
        assert!((arrow.left.y + arrow.right.y - 30.0).abs() < 0.001);
        let tiny = Annotation {
            end: Point::new(6.0, 15.0),
            ..mark
        };
        assert!(arrow_geometry(tiny).is_none());
    }

    #[test]
    fn tools_start_unselected_and_toggle_back_to_move() {
        let mut marks = Markings::new(100, 80);
        assert_eq!(marks.tool, Tool::Move);
        marks.begin(Point::new(5.0, 5.0));
        assert!(marks.draft.is_none());
        marks.select_tool(Tool::Rectangle);
        marks.begin(Point::new(5.0, 5.0));
        marks.select_tool(Tool::Rectangle);
        assert_eq!(marks.tool, Tool::Move);
        assert!(marks.draft.is_none());
        marks.select_tool(Tool::Arrow);
        assert_eq!(marks.tool, Tool::Arrow);
    }

    #[test]
    fn dragging_preserves_size_and_clamps_to_original_output() {
        let monitor = Rect::new(-1920, -100, 1920, 1080).unwrap();
        let origin = Rect::new(-1000, 300, 400, 300).unwrap();
        let drag = Drag {
            origin,
            pointer: Point::new(-900.0, 400.0),
        };
        let moved = drag.position(Point::new(-800.0, 450.0), monitor);
        assert_eq!(moved, Rect::new(-900, 350, 400, 300).unwrap());
        assert_eq!(
            drag.position(Point::new(-10000.0, -10000.0), monitor),
            Rect::new(-1920, -100, 400, 300).unwrap()
        );
        assert_eq!(
            drag.position(Point::new(10000.0, 10000.0), monitor),
            Rect::new(-400, 680, 400, 300).unwrap()
        );
        assert_eq!(drag.position(Point::new(f32::NAN, 0.0), monitor), origin);
    }

    #[test]
    fn toolbar_stays_on_output_without_moving_image() {
        let monitor = Rect::new(-1920, 0, 1920, 1080).unwrap();
        for image in [
            Rect::new(-1900, 20, 100, 50).unwrap(),
            Rect::new(-1000, 400, 300, 200).unwrap(),
            monitor,
        ] {
            let controls = toolbar_rect(image, monitor);
            assert!(monitor.contains(controls));
        }
    }
}
