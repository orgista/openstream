package com.orgista.openstream.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.domain.AdminPinPolicy

/**
 * Guardian gate for Settings and source management on a kids-locked install.
 * Verifies the stored admin PIN, or — on installs from before the PIN existed
 * — lets the guardian create one the first time the gate is opened.
 */
@Composable
fun AdminPinDialog(
    configured: Boolean,
    onVerify: (String) -> Boolean,
    onCreate: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var pin by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val digitsOnly: (String) -> String = { value -> value.filter(Char::isDigit).take(AdminPinPolicy.MAX_LENGTH) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                if (configured) "Enter admin PIN" else "Create admin PIN",
                fontWeight = FontWeight.ExtraBold,
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    if (configured) {
                        "Settings and sources are for guardians on this device."
                    } else {
                        "This install predates the admin PIN. Create one now — guardians enter it to open Settings and manage sources. It never unlocks Kids Mode itself."
                    },
                    color = OpenStreamColors.TextSoft,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                )
                OutlinedTextField(
                    value = pin,
                    onValueChange = { pin = digitsOnly(it); error = null },
                    singleLine = true,
                    label = { Text("PIN (${AdminPinPolicy.MIN_LENGTH}-${AdminPinPolicy.MAX_LENGTH} digits)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                )
                if (!configured) {
                    OutlinedTextField(
                        value = confirm,
                        onValueChange = { confirm = digitsOnly(it); error = null },
                        singleLine = true,
                        label = { Text("Confirm PIN") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        visualTransformation = PasswordVisualTransformation(),
                    )
                }
                error?.let {
                    Text(
                        it,
                        modifier = androidx.compose.ui.Modifier.semantics {
                            liveRegion = LiveRegionMode.Polite
                        },
                        color = OpenStreamColors.Danger,
                        fontSize = 13.sp,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    when {
                        !AdminPinPolicy.isValidPin(pin) ->
                            error = "Enter ${AdminPinPolicy.MIN_LENGTH} to ${AdminPinPolicy.MAX_LENGTH} digits."
                        !configured && pin != confirm -> error = "The PINs do not match."
                        configured && !onVerify(pin) -> error = "That PIN is not correct."
                        !configured -> onCreate(pin)
                    }
                },
                shape = OpenStreamShapes.Control,
            ) { Text(if (configured) "Unlock" else "Save PIN") }
        },
        dismissButton = { OpenStreamTextButton(onClick = onDismiss) { Text("Cancel") } },
        containerColor = OpenStreamColors.Surface,
        titleContentColor = OpenStreamColors.Text,
    )
}
