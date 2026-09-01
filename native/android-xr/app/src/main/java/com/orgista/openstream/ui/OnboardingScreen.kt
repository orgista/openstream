package com.orgista.openstream.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.domain.AdminPinPolicy
import com.orgista.openstream.domain.ContentPolicy
import com.orgista.openstream.domain.KidsCap
import com.orgista.openstream.domain.createKidsPolicy
import com.orgista.openstream.ui.icons.AppIcons

private enum class Step { MODE, RATING, BLOCKLIST, PIN, CONFIRM }

/**
 * First-run setup. The kids path creates a guardian admin PIN for Settings
 * and source management, then ends in an explicit irreversible confirmation:
 * the content filter itself has no exit — uninstalling the app (clearing its
 * data) is the only reset.
 */
@Composable
fun OnboardingScreen(
    onStandard: () -> Unit,
    onKids: (ContentPolicy.Kids) -> Unit,
) {
    var step by remember { mutableStateOf(Step.MODE) }
    var cap by remember { mutableStateOf(KidsCap.TEENS) }
    val blockedTerms = remember { mutableStateListOf<String>() }
    var termDraft by remember { mutableStateOf("") }
    var pinDraft by remember { mutableStateOf("") }
    var pinConfirm by remember { mutableStateOf("") }
    var acknowledged by remember { mutableStateOf(false) }

    BackHandler(enabled = step != Step.MODE) {
        acknowledged = false
        step = when (step) {
            Step.CONFIRM -> Step.PIN
            Step.PIN -> Step.BLOCKLIST
            Step.BLOCKLIST -> Step.RATING
            else -> Step.MODE
        }
    }

    Box(
        modifier = Modifier.fillMaxSize().background(OpenStreamColors.CanvasDeep),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 760.dp)
                .verticalScroll(rememberScrollState())
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            when (step) {
                Step.MODE -> {
                    Title(OnboardingCopy.MODE_TITLE)
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        if (maxWidth >= 700.dp) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                AudienceOption(
                                    title = "Everyone",
                                    modifier = Modifier.weight(1f),
                                    onClick = onStandard,
                                )
                                AudienceOption(
                                    title = "Kids Mode",
                                    warning = OnboardingCopy.KIDS_WARNING,
                                    modifier = Modifier.weight(1f),
                                    onClick = { step = Step.RATING },
                                )
                            }
                        } else {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                AudienceOption(
                                    title = "Everyone",
                                    onClick = onStandard,
                                )
                                AudienceOption(
                                    title = "Kids Mode",
                                    warning = OnboardingCopy.KIDS_WARNING,
                                    onClick = { step = Step.RATING },
                                )
                            }
                        }
                    }
                }

                Step.RATING -> {
                    Title(OnboardingCopy.AGE_TITLE)
                    KidsCap.entries.forEach { entry ->
                        ChoiceCard(
                            title = KidsAudiencePolicy.ageRange(entry),
                            onClick = {
                                cap = entry
                                step = Step.BLOCKLIST
                            },
                        )
                    }
                }

                Step.BLOCKLIST -> {
                    Title(OnboardingCopy.BLOCK_TITLE)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedTextField(
                            value = termDraft,
                            onValueChange = { termDraft = it.take(80) },
                            modifier = Modifier.weight(1f),
                            singleLine = true,
                            label = { Text("Title or word") },
                        )
                        Button(
                            onClick = {
                                val term = termDraft.trim().lowercase()
                                if (term.isNotEmpty() && term !in blockedTerms) blockedTerms.add(term)
                                termDraft = ""
                            },
                            enabled = termDraft.isNotBlank(),
                            shape = OpenStreamShapes.Control,
                        ) { Text("Add") }
                    }
                    if (blockedTerms.isNotEmpty()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                        ) {
                            blockedTerms.take(6).forEach { term ->
                                Surface(
                                    modifier = Modifier.semantics {
                                        contentDescription = "Remove $term"
                                        role = Role.Button
                                    },
                                    shape = OpenStreamShapes.Tag,
                                    color = OpenStreamColors.Coral.copy(alpha = 0.12f),
                                    border = BorderStroke(1.dp, OpenStreamColors.Coral.copy(alpha = 0.4f)),
                                    onClick = { blockedTerms.remove(term) },
                                ) {
                                    Text(
                                        "$term  ✕",
                                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                                        color = OpenStreamColors.Coral,
                                        fontSize = 14.sp,
                                    )
                                }
                            }
                        }
                        if (blockedTerms.size > 6) {
                            Text("+${blockedTerms.size - 6} more", color = OpenStreamColors.Muted, fontSize = 13.sp)
                        }
                    }
                    Button(onClick = { step = Step.PIN }, shape = OpenStreamShapes.Control) {
                        Text(OnboardingCopy.blockAction(blockedTerms.size))
                    }
                }

                Step.PIN -> {
                    Title(OnboardingCopy.PIN_TITLE)
                    OutlinedTextField(
                        value = pinDraft,
                        onValueChange = { pinDraft = it.filter(Char::isDigit).take(AdminPinPolicy.MAX_LENGTH) },
                        singleLine = true,
                        label = { Text("PIN (${AdminPinPolicy.MIN_LENGTH}-${AdminPinPolicy.MAX_LENGTH} digits)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        visualTransformation = PasswordVisualTransformation(),
                    )
                    OutlinedTextField(
                        value = pinConfirm,
                        onValueChange = { pinConfirm = it.filter(Char::isDigit).take(AdminPinPolicy.MAX_LENGTH) },
                        singleLine = true,
                        label = { Text("Confirm PIN") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        visualTransformation = PasswordVisualTransformation(),
                    )
                    if (pinConfirm.isNotEmpty() && pinConfirm != pinDraft) {
                        Text(
                            "PINs do not match.",
                            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                            color = OpenStreamColors.Amber,
                            fontSize = 14.sp,
                        )
                    }
                    Button(
                        onClick = { step = Step.CONFIRM },
                        enabled = AdminPinPolicy.isValidPin(pinDraft) && pinDraft == pinConfirm,
                        shape = OpenStreamShapes.Control,
                    ) { Text("Continue") }
                }

                Step.CONFIRM -> {
                    Icon(AppIcons.Warning, contentDescription = null, tint = OpenStreamColors.Amber, modifier = Modifier.size(48.dp))
                    Title(OnboardingCopy.CONFIRM_TITLE)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SummaryCell(KidsAudiencePolicy.ageRange(cap), cap.examples)
                        SummaryCell("${blockedTerms.size}", if (blockedTerms.size == 1) "blocked term" else "blocked terms")
                    }
                    Surface(
                        shape = OpenStreamShapes.Selection,
                        color = OpenStreamColors.Amber.copy(alpha = 0.1f),
                        border = BorderStroke(1.dp, OpenStreamColors.Amber.copy(alpha = 0.45f)),
                    ) {
                        Row(
                            modifier = Modifier.padding(18.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Icon(AppIcons.Lock, contentDescription = null, tint = OpenStreamColors.Amber, modifier = Modifier.size(22.dp))
                            Text(
                                OnboardingCopy.PERMANENCE,
                                color = OpenStreamColors.Amber.copy(alpha = 0.95f),
                                fontSize = 15.sp,
                                lineHeight = 22.sp,
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.toggleable(
                            value = acknowledged,
                            role = Role.Checkbox,
                            onValueChange = { acknowledged = it },
                        ).padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Checkbox(
                            checked = acknowledged,
                            onCheckedChange = null,
                            colors = CheckboxDefaults.colors(checkedColor = OpenStreamColors.Amber),
                        )
                        Text(OnboardingCopy.ACKNOWLEDGEMENT, color = OpenStreamColors.TextSoft)
                    }
                    Button(
                        onClick = { onKids(createKidsPolicy(cap, blockedTerms.toList(), pinDraft)) },
                        enabled = acknowledged,
                        shape = OpenStreamShapes.Control,
                        colors = ButtonDefaults.buttonColors(containerColor = OpenStreamColors.Amber, contentColor = OpenStreamColors.CanvasDeep),
                    ) {
                        Icon(AppIcons.Lock, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text("  Turn on Kids Mode", fontWeight = FontWeight.Bold)
                    }
                }
            }

            if (step != Step.MODE) {
                OpenStreamTextButton(onClick = {
                    acknowledged = false
                    step = when (step) {
                        Step.CONFIRM -> Step.PIN
                        Step.PIN -> Step.BLOCKLIST
                        Step.BLOCKLIST -> Step.RATING
                        else -> Step.MODE
                    }
                }) { Text("Back", color = OpenStreamColors.Muted) }
            }
        }
    }
}

@Composable
private fun Title(text: String) {
    Text(
        text,
        modifier = Modifier.semantics { heading() },
        fontSize = 34.sp,
        fontWeight = FontWeight.ExtraBold,
        color = OpenStreamColors.Text,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun ChoiceCard(
    title: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = OpenStreamShapes.Selection,
        color = OpenStreamColors.Surface,
        border = BorderStroke(1.dp, OpenStreamColors.BorderStrong),
    ) {
        Text(
            title,
            modifier = Modifier.padding(horizontal = 22.dp, vertical = 18.dp),
            fontSize = 21.sp,
            fontWeight = FontWeight.ExtraBold,
            color = OpenStreamColors.Text,
        )
    }
}

@Composable
private fun AudienceOption(
    title: String,
    modifier: Modifier = Modifier,
    warning: String? = null,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = OpenStreamShapes.Selection,
        color = OpenStreamColors.Surface,
        border = BorderStroke(1.dp, OpenStreamColors.BorderStrong),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 22.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(title, fontSize = 21.sp, fontWeight = FontWeight.ExtraBold, color = OpenStreamColors.Text)
            if (warning != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(AppIcons.Lock, contentDescription = null, tint = OpenStreamColors.Amber, modifier = Modifier.size(14.dp))
                    Text(warning, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Amber)
                }
            }
        }
    }
}

@Composable
private fun SummaryCell(value: String, label: String) {
    Surface(shape = OpenStreamShapes.Selection, color = OpenStreamColors.Surface, border = BorderStroke(1.dp, OpenStreamColors.Border)) {
        Column(Modifier.padding(horizontal = 22.dp, vertical = 12.dp).width(160.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = OpenStreamColors.Text)
            Text(label, fontSize = 13.sp, color = OpenStreamColors.Muted)
        }
    }
}
