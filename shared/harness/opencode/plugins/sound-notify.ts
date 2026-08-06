import type { Plugin, PluginInput } from "@opencode-ai/plugin"

// ponytail: macOS gets a built-in default; elsewhere the sound is opt-in via
// OPENCODE_NOTIFY_SOUND_COMMAND (the VM points it at the SSH tunnel back to the
// Mac), falling back to a terminal bell.
const DEFAULT_SOUND_COMMAND =
  process.platform === "darwin" ? "afplay /System/Library/Sounds/Glass.aiff" : ""
const SOUND_COMMAND = process.env.OPENCODE_NOTIFY_SOUND_COMMAND?.trim() || DEFAULT_SOUND_COMMAND
const MIN_SOUND_GAP_MS = 750

const playSound = async (ctx: PluginInput, lastPlayedAt: { value: number }) => {
  const now = Date.now()
  if (now - lastPlayedAt.value < MIN_SOUND_GAP_MS) return

  lastPlayedAt.value = now
  if (SOUND_COMMAND) {
    await ctx.$`sh -lc ${SOUND_COMMAND}`.quiet().nothrow()
    return
  }

  process.stderr.write("\x07")
}

export const SoundNotifyPlugin: Plugin = async (ctx) => {
  const busySessions = new Set<string>()
  const lastPlayedAt = { value: 0 }

  return {
    event: async ({ event }) => {
      if (event.type === "question.asked" || event.type === "permission.asked") {
        await playSound(ctx, lastPlayedAt)
        return
      }

      if (event.type === "session.status") {
        if (event.properties.status.type === "busy") {
          busySessions.add(event.properties.sessionID)
          return
        }

        if (event.properties.status.type === "idle" && busySessions.delete(event.properties.sessionID)) {
          await playSound(ctx, lastPlayedAt)
        }
        return
      }

      if (event.type === "session.idle" && busySessions.delete(event.properties.sessionID)) {
        await playSound(ctx, lastPlayedAt)
      }
    },
  }
}

export default SoundNotifyPlugin
