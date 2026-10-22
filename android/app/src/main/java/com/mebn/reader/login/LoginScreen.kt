package com.mebn.reader.login

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.mebn.reader.R
import com.mebn.reader.app.AppModel
import com.mebn.reader.sync.Api
import com.mebn.reader.sync.DeviceInfo
import com.mebn.reader.sync.Session
import com.mebn.reader.ui.literata
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Signing in, made to look like the other apps': the book over warm paper, then Google or email. */
@Composable
fun LoginScreen() {
    var email by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize()) {
        Backdrop()
        BoxWithConstraints(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
            val hero = (maxHeight * 0.16f).coerceIn(80.dp, 140.dp)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Hero(hero)
                Headline(Modifier.padding(top = 28.dp))
                Box(Modifier.widthIn(max = 384.dp).fillMaxWidth().padding(top = 32.dp)) {
                    AnimatedContent(email, transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }, label = "step") { showEmail ->
                        if (showEmail) EmailStep { email = false } else ChooseStep { email = true }
                    }
                }
            }
        }
    }
}

/** Soft colour that slowly wanders behind everything, over faintly ruled paper. */
@Composable
private fun Backdrop() {
    val dark = isSystemInDarkTheme()
    val drift by rememberInfiniteTransition(label = "drift").animateFloat(0f, 1f, infiniteRepeatable(tween(9000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "drift")
    Box(Modifier.fillMaxSize().background(Color(if (dark) 0xff171411 else 0xfffbf7ee))) {
        Canvas(Modifier.fillMaxSize().blur(64.dp)) {
            fun blob(color: Color, radius: Float, x: Float, y: Float, dx: Float, dy: Float) =
                drawCircle(color, radius * (1 + 0.15f * drift), Offset(x + dx * drift, y + dy * drift))
            blob(if (dark) Color(0x33c9532c) else Color(0x73f0b98a), 180.dp.toPx(), 60.dp.toPx(), size.height * 0.2f, 60.dp.toPx(), 40.dp.toPx())
            blob(if (dark) Color(0x4046607f) else Color(0x739ec4b0), 190.dp.toPx(), size.width - 40.dp.toPx(), size.height * 0.45f, -50.dp.toPx(), -30.dp.toPx())
            blob(if (dark) Color(0x1fe0a93c) else Color(0x73f3d58a), 210.dp.toPx(), size.width * 0.4f, size.height - 40.dp.toPx(), 40.dp.toPx(), -40.dp.toPx())
        }
        Canvas(Modifier.fillMaxSize()) {
            val line = Color(0xff786450).copy(alpha = if (dark) 0.05f else 0.03f)
            var y = 31.dp.toPx()
            while (y < size.height) {
                drawRect(line, Offset(0f, y), Size(size.width, 1.dp.toPx()))
                y += 32.dp.toPx()
            }
        }
    }
}

/** The app's book, floating gently. */
@Composable
private fun Hero(size: androidx.compose.ui.unit.Dp) {
    val float by rememberInfiniteTransition(label = "float").animateFloat(0f, 1f, infiniteRepeatable(tween(3200, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "float")
    Image(
        painterResource(R.drawable.ic_launcher_art), null,
        Modifier.size(size).graphicsLayer { translationY = -6.dp.toPx() * float }.shadow(18.dp, RoundedCornerShape(size * 0.22f)).clip(RoundedCornerShape(size * 0.22f)),
    )
}

@Composable
private fun Headline(modifier: Modifier) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val alpha by androidx.compose.animation.core.animateFloatAsState(if (shown) 1f else 0f, tween(700, 300), label = "headline")
    Column(modifier.graphicsLayer { this.alpha = alpha; translationY = (1 - alpha) * 24.dp.toPx() }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Reader", fontFamily = literata(500), fontSize = 48.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onBackground)
        Text("Every book, everywhere.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ChooseStep(onEmail: () -> Unit) {
    val context = LocalContext.current
    val dark = isSystemInDarkTheme()
    val scope = rememberCoroutineScope()
    var waiting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var job by remember { mutableStateOf<Job?>(null) }
    val google = remember { GoogleSignIn() }
    // Coming back to the app is how the person finishes or gives up on Google's page.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) google.returned = true }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            job?.cancel()
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Pill(
            onClick = {
                error = ""
                waiting = true
                job = scope.launch {
                    try {
                        google.run(context)?.let(AppModel::signIn)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = e.message ?: "Couldn't sign in with Google"
                    } finally {
                        waiting = false
                    }
                }
            },
            container = Color.White, content = Color(0xff1f1f1f), enabled = !waiting, border = true,
        ) {
            if (waiting) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Color(0xff1f1f1f)) else GoogleMark(Modifier.size(20.dp))
            Text(if (waiting) "Waiting for Google…" else "Continue with Google", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        }
        Pill(onClick = onEmail, container = if (dark) Color.White.copy(alpha = 0.1f) else Color(0xff2b2622), content = Color.White) {
            Icon(Icons.Outlined.Email, null)
            Text("Continue with email", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        }
        if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
    }
}

@Composable
private fun EmailStep(onBack: () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scope = rememberCoroutineScope()
    var signUp by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf(AppModel.session?.email ?: "") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val emailFocus = remember { FocusRequester() }
    val passwordFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        delay(350)
        runCatching { (if (email.isEmpty()) emailFocus else passwordFocus).requestFocus() }
    }

    fun submit() {
        if (busy) return
        if (email.isEmpty() || password.isEmpty()) {
            runCatching { (if (email.isEmpty()) emailFocus else passwordFocus).requestFocus() }
            return
        }
        if (signUp && password.length < 8) {
            error = "Password must be at least 8 characters"
            return
        }
        busy = true
        error = ""
        scope.launch {
            try {
                val server = Session.DEFAULT_SERVER
                val (token, user) = if (signUp) Api.register(server, email.trim(), password, DeviceInfo.current) else Api.login(server, email.trim(), password, DeviceInfo.current)
                AppModel.signIn(Session(server, token, user.email))
            } catch (e: Exception) {
                error = e.message ?: "Couldn't sign in"
            } finally {
                busy = false
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Field(email, { email = it }, "Email", Modifier.focusRequester(emailFocus), KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next), KeyboardActions { passwordFocus.requestFocus() })
        Field(password, { password = it }, "Password", Modifier.focusRequester(passwordFocus), KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go), KeyboardActions { submit() }, secret = true)
        if (error.isNotEmpty()) Text(error, Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
        Pill(onClick = ::submit, container = if (dark) Color(0xfff1ece4) else Color(0xff2b2622), content = if (dark) Color(0xff171411) else Color.White, enabled = !busy) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = if (dark) Color.Black else Color.White)
            Text(if (signUp) "Create account" else "Sign in", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Back", Modifier.padding(start = 6.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton({
                signUp = !signUp
                error = ""
            }) { Text(if (signUp) "I have an account" else "Create account", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun Field(value: String, onChange: (String) -> Unit, label: String, modifier: Modifier, keyboard: KeyboardOptions, actions: KeyboardActions, secret: Boolean = false) {
    val dark = isSystemInDarkTheme()
    TextField(
        value, onChange,
        modifier.fillMaxWidth().border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CircleShape),
        placeholder = { Text(label) },
        singleLine = true,
        shape = CircleShape,
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = keyboard,
        keyboardActions = actions,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = if (dark) Color.White.copy(alpha = 0.06f) else Color.White.copy(alpha = 0.85f),
            unfocusedContainerColor = if (dark) Color.White.copy(alpha = 0.05f) else Color.White.copy(alpha = 0.8f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
private fun Pill(onClick: () -> Unit, container: Color, content: Color, enabled: Boolean = true, border: Boolean = false, label: @Composable () -> Unit) {
    Button(
        onClick,
        Modifier.fillMaxWidth().height(52.dp).then(if (border) Modifier.border(1.dp, Color.Black.copy(alpha = 0.05f), CircleShape) else Modifier),
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = container, contentColor = content, disabledContainerColor = container, disabledContentColor = content),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp, pressedElevation = 1.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) { label() }
    }
}

/** Google's "G": four arcs of a ring and the bar into its middle. */
@Composable
private fun GoogleMark(modifier: Modifier) {
    Canvas(modifier) {
        val s = size.width / 48
        val ring = Stroke(10 * s)
        val box = Size(38 * s, 38 * s)
        val at = Offset(5 * s, 5 * s)
        fun arc(from: Float, to: Float, color: Long) = drawArc(Color(color), from, to - from, false, at, box, style = ring)
        arc(-140f, -42f, 0xffea4335)
        arc(150f, 220f, 0xfffbbc05)
        arc(42f, 150f, 0xff34a853)
        arc(0f, 42f, 0xff4285f4)
        drawRect(Color(0xff4285f4), Offset(24 * s, 19.5f * s), Size(22 * s, 9 * s))
    }
}
