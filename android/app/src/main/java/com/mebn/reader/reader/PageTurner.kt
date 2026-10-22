package com.mebn.reader.reader

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlin.math.abs

/** What a touch on the pages can do besides turning them. Points are in the turner's own pixels. */
interface PageGestures {
    fun onTap(point: Offset)
    /** Starts selecting at a long press; false when there's nothing to select there. */
    fun beginSelection(point: Offset): Boolean = false
    fun extendSelection(point: Offset) {}
    fun endSelection() {}
    /** Which selection handle is under a point, if any: 0 the start, 1 the end. */
    fun handleAt(point: Offset): Int? = null
    fun dragHandle(handle: Int, point: Offset) {}
    fun endHandle() {}
    /** A page is being dragged. */
    fun onDragStart() {}
}

/**
 * Turns pages like sheets of paper: the page on top slides away to uncover the next, or the
 * previous one slides back over it. Driven by drags, flings and [turn].
 */
class PageTurner {
    /** The view's own scope, whose frame clock runs the slides; null until it's shown. */
    var scope: CoroutineScope? = null
    val offset = Animatable(0f)
    var width by mutableFloatStateOf(0f)
    var canTurn: (forward: Boolean) -> Boolean = { false }
    var commit: (forward: Boolean) -> Unit = {}
    private var turning: Job? = null
    /** The direction of a turn that's sliding and not yet made. */
    private var pending: Boolean? = null

    /** Runs after any turn in progress, which is finished at once. */
    private fun next(block: suspend () -> Unit) {
        val scope = scope ?: return
        val previous = turning
        turning = scope.launch {
            previous?.cancelAndJoin()
            pending?.let { finish(it) }
            block()
        }
    }

    /** Makes the turn, in the same frame as the slide resets, so nothing flickers. */
    private suspend fun finish(forward: Boolean) {
        pending = null
        offset.snapTo(0f)
        commit(forward)
    }

    /** Turns with the slide; a turn asked for mid-slide finishes the first at once. */
    fun turn(forward: Boolean) = next {
        if (!canTurn(forward) || width <= 0f) return@next
        pending = forward
        offset.animateTo(if (forward) -width else width, tween(280))
        finish(forward)
    }

    /** Lets go of a drag, finishing or undoing the turn. */
    fun release(velocity: Float) = next {
        val o = offset.value
        val forward = o < 0
        val done = o != 0f && canTurn(forward) && (abs(o) > width * 0.25f || (abs(velocity) > 900f && (velocity < 0) == forward))
        if (done) {
            pending = forward
            offset.animateTo(if (forward) -width else width, tween(220))
            finish(forward)
        } else {
            offset.animateTo(0f, tween(200))
        }
    }

    fun drag(by: Float) = next {
        var target = offset.value + by
        // Pages that aren't there only give a little.
        if (target < 0 && !canTurn(true)) target = maxOf(target, -width * 0.06f)
        if (target > 0 && !canTurn(false)) target = minOf(target, width * 0.06f)
        offset.snapTo(target.coerceIn(-width, width))
    }
}

/** Shows the current page with its neighbors ready to slide in. `page(-1)`, `page(0)` and `page(1)` draw them. */
@Composable
fun PageTurnerView(
    turner: PageTurner,
    gestures: PageGestures,
    modifier: Modifier = Modifier,
    background: Color,
    page: @Composable (Int) -> Unit,
) {
    val slop = LocalViewConfiguration.current.touchSlop
    turner.scope = rememberCoroutineScope()
    val shadow = with(LocalDensity.current) { 18.dp.toPx() }
    Box(
        modifier
            .fillMaxSize()
            .clipToBounds()
            .onSizeChanged { turner.width = it.width.toFloat() }
            .pointerInput(turner, gestures) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val handle = gestures.handleAt(down.position)
                    if (handle != null) {
                        down.consume()
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            change.consume()
                            gestures.dragHandle(handle, change.position)
                        }
                        gestures.endHandle()
                        return@awaitEachGesture
                    }

                    // A tap, a drag, or a long press that selects.
                    var moved: Offset? = null
                    var lifted = false
                    val timedOut = withTimeoutOrNull(380) {
                        while (true) {
                            val change = awaitPointerEvent(PointerEventPass.Main).changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) {
                                lifted = true
                                break
                            }
                            val distance = change.position - down.position
                            if (distance.getDistance() > slop) {
                                moved = distance
                                break
                            }
                        }
                    } == null

                    if (lifted) {
                        gestures.onTap(down.position)
                        return@awaitEachGesture
                    }
                    if (timedOut && moved == null) {
                        if (!gestures.beginSelection(down.position)) return@awaitEachGesture
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            change.consume()
                            gestures.extendSelection(change.position)
                        }
                        gestures.endSelection()
                        return@awaitEachGesture
                    }
                    val distance = moved ?: return@awaitEachGesture
                    // Mostly up or down isn't a page turn.
                    if (abs(distance.y) > abs(distance.x)) return@awaitEachGesture

                    gestures.onDragStart()
                    val tracker = VelocityTracker()
                    tracker.addPosition(down.uptimeMillis, down.position)
                    turner.drag(distance.x)
                    while (true) {
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                        tracker.addPosition(change.uptimeMillis, change.position)
                        if (!change.pressed) break
                        change.consume()
                        turner.drag(change.positionChange().x)
                    }
                    turner.release(tracker.calculateVelocity().x)
                }
            },
    ) {
        // Turning forward, the current page slides off the next one; turning back, the
        // previous page slides over the current one.
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (turner.offset.value < 0) 1f else 0f }.drawBehind { drawRect(background) }) { page(1) }
        Box(
            Modifier.fillMaxSize().graphicsLayer { translationX = minOf(0f, turner.offset.value) }
                .edgeShadow(background, shadow, { turner.offset.value < 0 }),
        ) { page(0) }
        Box(
            Modifier.fillMaxSize().graphicsLayer {
                val o = turner.offset.value
                translationX = if (o > 0) o - size.width else -size.width
                alpha = if (o > 0) 1f else 0f
            }.edgeShadow(background, shadow, { turner.offset.value > 0 }),
        ) { page(-1) }
    }
}

/** The page's own color, with a soft shadow off its right edge while it moves. */
private fun Modifier.edgeShadow(background: Color, width: Float, active: () -> Boolean) = drawWithContent {
    drawRect(background)
    drawContent()
    if (active()) {
        drawRect(
            Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.22f), Color.Transparent), startX = size.width, endX = size.width + width),
            topLeft = Offset(size.width, 0f),
            size = size.copy(width = width),
        )
    }
}
