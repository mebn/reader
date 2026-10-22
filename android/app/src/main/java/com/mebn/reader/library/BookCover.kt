package com.mebn.reader.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import com.mebn.reader.model.Book
import com.mebn.reader.sync.Api
import com.mebn.reader.sync.SyncEngine
import com.mebn.reader.ui.literata

private val tints = listOf(0xff5b6b7a, 0xff7a5b5b, 0xff5b7a65, 0xff6d5b7a, 0xff7a6d5b, 0xff4f6f78, 0xff7a5b6f, 0xff62705a).map { Color(it) }

/** The same tint the desktop app picks for a title. */
fun coverTint(seed: String): Color {
    var h = 0
    for (c in seed) h = h * 31 + c.code
    return tints[(h.toUInt() % tints.size.toUInt()).toInt()]
}

/** The cover's address on the server, which changes when the book does. */
fun coverUrl(book: Book): String? {
    val session = SyncEngine.session ?: return null
    return if (book.hasCover) Api.coverUrl(session, book) else null
}

/** A book's cover, or a typographic stand-in when it has none. */
@Composable
fun BookCover(book: Book, modifier: Modifier = Modifier, corner: Dp = 6.dp) {
    val shape = RoundedCornerShape(corner)
    Box(
        modifier
            .aspectRatio(2f / 3f)
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f), shape),
    ) {
        val url = coverUrl(book)
        if (url != null) {
            SubcomposeAsyncImage(
                url, book.title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop,
                loading = { Placeholder(book) }, error = { Placeholder(book) },
            )
        } else {
            Placeholder(book)
        }
        // The spine's shadow.
        Box(
            Modifier.fillMaxHeight().fillMaxWidth(0.05f)
                .background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.15f), Color.Transparent))),
        )
    }
}

@Composable
private fun Placeholder(book: Book) {
    val tint = coverTint(book.title)
    BoxWithConstraints(
        Modifier.fillMaxSize().background(Brush.linearGradient(listOf(tint, lerp(tint, Color.Black, 0.35f)))),
    ) {
        val w = maxWidth
        val density = LocalDensity.current
        Column(Modifier.fillMaxSize().padding(w * 0.09f)) {
            Text(
                book.title, color = Color.White, fontFamily = literata(500), fontWeight = FontWeight.Medium,
                fontSize = with(density) { (w * 0.12f).coerceAtLeast(9.dp).toSp() }, lineHeight = with(density) { (w * 0.15f).coerceAtLeast(11.dp).toSp() },
                maxLines = 5, overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.weight(1f))
            Text(
                book.author, color = Color.White.copy(alpha = 0.75f),
                fontSize = with(density) { (w * 0.08f).coerceAtLeast(7.dp).toSp() }, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
