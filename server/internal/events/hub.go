package events

import "sync"

// Hub fans out change notifications to every connected device of a user.
type Hub struct {
	mu   sync.Mutex
	subs map[string]map[chan int64]struct{}
}

func NewHub() *Hub {
	return &Hub{subs: map[string]map[chan int64]struct{}{}}
}

func (h *Hub) Subscribe(userID string) (<-chan int64, func()) {
	ch := make(chan int64, 1)
	h.mu.Lock()
	if h.subs[userID] == nil {
		h.subs[userID] = map[chan int64]struct{}{}
	}
	h.subs[userID][ch] = struct{}{}
	h.mu.Unlock()

	return ch, func() {
		h.mu.Lock()
		delete(h.subs[userID], ch)
		if len(h.subs[userID]) == 0 {
			delete(h.subs, userID)
		}
		h.mu.Unlock()
	}
}

// Publish notifies subscribers that data up to version has changed.
// Slow subscribers only ever hold the latest version.
func (h *Hub) Publish(userID string, version int64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs[userID] {
		select {
		case <-ch:
		default:
		}
		ch <- version
	}
}
