package events

import "sync"

// subscription is one open event stream, from one device.
type subscription struct {
	deviceID string
	updates  chan int64
	// closed is closed when the device is signed out, ending its stream.
	closed chan struct{}
}

// Hub fans out change notifications to every connected device of a user.
type Hub struct {
	mu   sync.Mutex
	subs map[string]map[*subscription]struct{}
}

func NewHub() *Hub {
	return &Hub{subs: map[string]map[*subscription]struct{}{}}
}

// Subscribe opens a stream for a device. Updates carry the newest version; closed
// fires when the device is signed out.
func (h *Hub) Subscribe(userID, deviceID string) (updates <-chan int64, closed <-chan struct{}, unsubscribe func()) {
	sub := &subscription{deviceID: deviceID, updates: make(chan int64, 1), closed: make(chan struct{})}
	h.mu.Lock()
	if h.subs[userID] == nil {
		h.subs[userID] = map[*subscription]struct{}{}
	}
	h.subs[userID][sub] = struct{}{}
	h.mu.Unlock()

	return sub.updates, sub.closed, func() {
		h.mu.Lock()
		delete(h.subs[userID], sub)
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
	for sub := range h.subs[userID] {
		select {
		case <-sub.updates:
		default:
		}
		sub.updates <- version
	}
}

// Online reports which of a user's devices have a stream open right now.
func (h *Hub) Online(userID string) map[string]bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	online := map[string]bool{}
	for sub := range h.subs[userID] {
		if sub.deviceID != "" {
			online[sub.deviceID] = true
		}
	}
	return online
}

// Disconnect ends a device's streams, so it reconnects and finds itself signed out.
func (h *Hub) Disconnect(userID, deviceID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for sub := range h.subs[userID] {
		if sub.deviceID == deviceID {
			select {
			case <-sub.closed:
			default:
				close(sub.closed)
			}
		}
	}
}
