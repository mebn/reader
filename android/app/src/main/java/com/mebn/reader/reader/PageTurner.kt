package com.mebn.reader.reader

import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOutCubic
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalViewConfiguration
import com.mebn.reader.model.PageTurn
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
    /** A swipe is about to turn the page. */
    fun onSwipe() {}
}

/**
 * Turns pages at once, with a crossfade, or by sliding the next page in, as [style] says.
 * A turn asked for while another is showing finishes that one at once, so quick taps never
 * queue up.
 */
class PageTurner {
    /** The view's own scope, whose frame clock runs the animations; null until it's shown. */
    var scope: CoroutineScope? = null
    var style = PageTurn.SLIDE
    /** How far the turn has come, 0 to 1. */
    val progress = Animatable(0f)
    /** The direction of a turn that's showing and not yet made. */
    var pending by mutableStateOf<Boolean?>(null)
        private set
    var width by mutableFloatStateOf(0f)
    var canTurn: (forward: Boolean) -> Boolean = { false }
    var commit: (forward: Boolean) -> Unit = {}
    private var turning: Job? = null

    /** Makes the turn, in the same frame as the animation resets, so nothing flickers. */
    private suspend fun finish(forward: Boolean) {
        pending = null
        progress.snapTo(0f)
        commit(forward)
    }

    fun turn(forward: Boolean) {
        val scope = scope ?: return
        val previous = turning
        turning = scope.launch {
            previous?.cancelAndJoin()
            pending?.let { finish(it) }
            if (!canTurn(forward)) return@launch
            // With animations off in the system settings, every turn is instant.
            val style = if (ValueAnimator.areAnimatorsEnabled() && width > 0f) style else PageTurn.INSTANT
            if (style != PageTurn.INSTANT) {
                pending = forward
                progress.animateTo(1f, if (style == PageTurn.FADE) tween(200, easing = LinearEasing) else tween(250, easing = EaseOutCubic))
            }
            finish(forward)
        }
    }
}

/** Shows the current page, and the one it's turning to. `page(-1)`, `page(0)` and `page(1)` draw them. */
@Composable
fun PageTurnerView(
    turner: PageTurner,
    gestures: PageGestures,
    style: PageTurn,
    modifier: Modifier = Modifier,
    background: Color,
    page: @Composable (Int) -> Unit,
) {
    val slop = LocalViewConfiguration.current.touchSlop
    turner.scope = rememberCoroutineScope()
    turner.style = style
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

                    // A tap, a swipe, or a long press that selects.
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

                    // The swipe turns once, right away; the rest of it is ignored.
                    gestures.onSwipe()
                    turner.turn(distance.x < 0)
                    while (true) {
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        change.consume()
                    }
                }
            },
    ) {
        // Sliding, the current page moves off one side as the next comes in from the other.
        // Fading, the current page fades out over the next.
        for (offset in listOf(-1, 1, 0)) {
            Box(
                Modifier.fillMaxSize().graphicsLayer {
                    val forward = turner.pending
                    val p = turner.progress.value
                    val shown = offset == 0 || forward == (offset > 0)
                    alpha = when {
                        !shown -> 0f
                        offset == 0 && turner.style == PageTurn.FADE && forward != null -> 1 - p
                        else -> 1f
                    }
                    translationX = when {
                        forward == null || turner.style != PageTurn.SLIDE || !shown -> 0f
                        offset == 0 -> if (forward) -p * size.width else p * size.width
                        else -> if (forward) (1 - p) * size.width else (p - 1) * size.width
                    }
                }.drawBehind { drawRect(background) },
            ) { page(offset) }
        }
    }
}
