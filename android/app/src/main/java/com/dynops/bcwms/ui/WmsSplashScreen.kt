package com.dynops.bcwms.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Kısa açılış ekranı: bağlantı ve şirket hazırlanırken boş beyaz ekran göstermez. */
@Composable
fun WmsSplashScreen(brand: CompanyBrand) {
    val transition = rememberInfiniteTransition(label = "wms-loader")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1100, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "wms-loader-rotation",
    )

    Box(
        Modifier.fillMaxSize().background(Brush.linearGradient(listOf(brand.primary, brand.secondary))),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(Modifier.size(126.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier.fillMaxSize().rotate(rotation).border(
                        width = 5.dp,
                        brush = Brush.sweepGradient(
                            listOf(Color.Transparent, Color.White.copy(alpha = 0.25f), Color.White),
                        ),
                        shape = CircleShape,
                    ),
                )
                Surface(
                    modifier = Modifier.size(102.dp),
                    shape = RoundedCornerShape(28.dp),
                    color = Color.White,
                    shadowElevation = 10.dp,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text("▥", fontSize = 30.sp, color = brand.primary, fontWeight = FontWeight.Black)
                        Text("WMS", fontSize = 18.sp, color = brand.primary, fontWeight = FontWeight.Black)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            CompanyLogo(brand = brand, height = 34.dp)
            Spacer(Modifier.height(20.dp))
            Text(
                "Depo hazırlanıyor…",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier.size(width = 72.dp, height = 4.dp).clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.32f)),
            )
        }
    }
}
