/// Stable identities keep asynchronous copy/save callbacks attached to their
/// own image, even when other images are captured, pinned, or closed.
pub type PinId = u64;

pub struct PinEntry<T> {
    pub id: PinId,
    pub pinned: bool,
    pub value: T,
}

pub struct PinStore<T> {
    entries: Vec<PinEntry<T>>,
    next_id: PinId,
}

impl<T> Default for PinStore<T> {
    fn default() -> Self {
        Self {
            entries: Vec::new(),
            next_id: 1,
        }
    }
}

impl<T> PinStore<T> {
    pub fn insert(&mut self, value: T) -> PinId {
        let id = self.next_id;
        self.next_id = self.next_id.checked_add(1).expect("pin identity exhausted");
        self.entries.push(PinEntry {
            id,
            pinned: false,
            value,
        });
        id
    }

    /// Successful captures replace only temporary images. Canceled or failed
    /// captures never call this method, so their previous image is restored.
    pub fn replace_unpinned(&mut self, value: T) -> PinId {
        self.entries.retain(|entry| entry.pinned);
        self.insert(value)
    }

    pub fn toggle_pin(&mut self, id: PinId) -> Option<bool> {
        let entry = self.get_mut(id)?;
        entry.pinned = !entry.pinned;
        Some(entry.pinned)
    }

    pub fn get(&self, id: PinId) -> Option<&PinEntry<T>> {
        self.entries.iter().find(|entry| entry.id == id)
    }

    pub fn get_mut(&mut self, id: PinId) -> Option<&mut PinEntry<T>> {
        self.entries.iter_mut().find(|entry| entry.id == id)
    }

    pub fn remove(&mut self, id: PinId) -> Option<PinEntry<T>> {
        let index = self.entries.iter().position(|entry| entry.id == id)?;
        Some(self.entries.remove(index))
    }

    pub fn iter(&self) -> impl Iterator<Item = &PinEntry<T>> {
        self.entries.iter()
    }

    pub fn iter_mut(&mut self) -> impl Iterator<Item = &mut PinEntry<T>> {
        self.entries.iter_mut()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_capture_replaces_the_previous_unpinned_image() {
        let mut store = PinStore::default();
        let first = store.insert("first");
        let second = store.replace_unpinned("second");
        assert!(store.get(first).is_none());
        assert_eq!(store.get(second).unwrap().value, "second");
        assert!(!store.get(second).unwrap().pinned);
        assert_eq!(store.iter().count(), 1);
    }

    #[test]
    fn pinned_images_and_their_edits_survive_successive_captures() {
        let mut store = PinStore::default();
        let first = store.insert(("first", (100, 200), vec!["rectangle", "arrow"]));
        assert_eq!(store.toggle_pin(first), Some(true));
        let second = store.replace_unpinned(("second", (0, 0), vec![]));
        let third = store.replace_unpinned(("third", (10, 20), vec![]));
        assert!(store.get(second).is_none());
        assert_eq!(
            store.get(first).unwrap().value,
            ("first", (100, 200), vec!["rectangle", "arrow"])
        );
        assert!(store.get(third).is_some());
        assert_eq!(store.iter().count(), 2);
    }

    #[test]
    fn multiple_pinned_images_survive_and_can_be_unpinned_again() {
        let mut store = PinStore::default();
        let a = store.insert("a");
        store.toggle_pin(a);
        let b = store.replace_unpinned("b");
        store.toggle_pin(b);
        let c = store.replace_unpinned("c");
        assert_eq!(store.iter().count(), 3);
        assert_eq!(store.toggle_pin(a), Some(false));
        let d = store.replace_unpinned("d");
        assert!(store.get(a).is_none());
        assert!(store.get(c).is_none());
        assert_eq!(store.get(b).unwrap().value, "b");
        assert_eq!(store.get(d).unwrap().value, "d");
    }

    #[test]
    fn copy_or_close_removes_only_its_own_image_and_never_reuses_an_id() {
        let mut store = PinStore::default();
        let pinned = store.insert("pinned");
        store.toggle_pin(pinned);
        let temporary = store.replace_unpinned("temporary");
        store.remove(temporary);
        assert_eq!(store.get(pinned).unwrap().value, "pinned");
        let newer = store.insert("newer");
        assert!(newer > temporary);
        assert!(store.remove(temporary).is_none());
        assert!(store.get(newer).is_some());
        store.remove(pinned);
        store.remove(newer);
        assert!(store.is_empty());
    }

    #[test]
    fn canceling_capture_does_not_replace_any_document_or_pin_state() {
        let mut store = PinStore::default();
        let pinned = store.insert("pinned");
        store.toggle_pin(pinned);
        let temporary = store.insert("temporary");
        let temporarily_hidden: Vec<_> = store
            .iter()
            .filter(|entry| !entry.pinned)
            .map(|entry| entry.id)
            .collect();
        assert_eq!(temporarily_hidden, vec![temporary]);
        assert!(store.get(pinned).unwrap().pinned);
        assert_eq!(store.get(temporary).unwrap().value, "temporary");
    }
}
