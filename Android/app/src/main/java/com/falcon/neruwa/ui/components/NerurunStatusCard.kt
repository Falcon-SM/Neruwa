package com.falcon.neruwa.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.falcon.neruwa.R
import com.falcon.neruwa.model.NerurunCondition
import com.falcon.neruwa.model.NerurunStatus
import io.github.sceneview.Scene
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberNodes
import io.github.sceneview.node.ModelNode

@Composable
fun NerurunStatusCard(
    status: NerurunStatus,
    modifier: Modifier = Modifier
) {
    val tint = when (status.condition) {
        NerurunCondition.NORMAL -> MaterialTheme.colorScheme.primary
        NerurunCondition.DISCOURAGED, NerurunCondition.THRIVING -> Color(0xFF65D68A)
        NerurunCondition.EXHAUSTED -> Color(0xFFFF9A58)
    }
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f))
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text("ねるるんの様子", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(
                            imageVector = when (status.condition) {
                                NerurunCondition.NORMAL -> Icons.Default.AutoAwesome
                                NerurunCondition.DISCOURAGED -> Icons.Default.Eco
                                NerurunCondition.EXHAUSTED -> Icons.Default.NightsStay
                                NerurunCondition.THRIVING -> Icons.Default.Pets
                            },
                            contentDescription = null,
                            tint = tint,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(status.condition.title, color = tint, fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.weight(1f))
                if (status.condition == NerurunCondition.THRIVING) {
                    Text(
                        "+${status.companionCount}",
                        modifier = Modifier.background(Color(0xFF1D5138), CircleShape).padding(horizontal = 12.dp, vertical = 6.dp),
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            RockingNerurun(status)
            Text(status.condition.message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RockingNerurun(status: NerurunStatus) {
    val (angle, duration) = when (status.condition) {
        NerurunCondition.NORMAL -> 3f to 1_800
        NerurunCondition.DISCOURAGED -> 2f to 2_100
        NerurunCondition.EXHAUSTED -> 1.2f to 2_500
        NerurunCondition.THRIVING -> 4f to 1_350
    }
    val transition = rememberInfiniteTransition(label = "nerurun-rock")
    val rotation = transition.animateFloat(
        initialValue = -angle,
        targetValue = angle,
        animationSpec = infiniteRepeatable(tween(duration), RepeatMode.Reverse),
        label = "rotation"
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(230.dp)
            .graphicsLayer {
                rotationZ = rotation.value
                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)
            },
        contentAlignment = Alignment.Center
    ) {
        NerurunScene(Modifier.fillMaxWidth().height(220.dp))

        if (status.condition == NerurunCondition.DISCOURAGED) {
            Text("☘️", fontSize = 30.sp, modifier = Modifier.offset(x = 68.dp, y = (-62).dp))
        }
        if (status.condition == NerurunCondition.EXHAUSTED) {
            Row(
                modifier = Modifier.offset(y = (-25).dp),
                horizontalArrangement = Arrangement.spacedBy(30.dp)
            ) {
                repeat(2) {
                    Box(
                        Modifier
                            .size(width = 30.dp, height = 7.dp)
                            .blur(1.dp)
                            .background(Color(0xFF7B4A32).copy(alpha = 0.65f), CircleShape)
                    )
                }
            }
        }
        if (status.condition == NerurunCondition.THRIVING) {
            Row(
                modifier = Modifier.align(Alignment.BottomCenter).offset(y = 4.dp),
                horizontalArrangement = Arrangement.spacedBy((-12).dp)
            ) {
                repeat(status.companionCount.coerceIn(0, 3)) {
                    Image(
                        painter = painterResource(R.drawable.nerurun_mascot),
                        contentDescription = "子どものねるるん",
                        modifier = Modifier.size(72.dp),
                        contentScale = ContentScale.Fit
                    )
                }
            }
        }
    }
}

@Composable
private fun NerurunScene(modifier: Modifier = Modifier) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val childNodes = rememberNodes {
        add(
            ModelNode(
                modelInstance = modelLoader.createModelInstance("models/nerurun.glb"),
                scaleToUnits = 1.8f
            )
        )
    }
    Scene(
        modifier = modifier,
        engine = engine,
        modelLoader = modelLoader,
        childNodes = childNodes,
        isOpaque = false
    )
}
