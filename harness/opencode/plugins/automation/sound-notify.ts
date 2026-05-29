import type { Plugin, PluginInput } from "@opencode-ai/plugin"

const DEFAULT_SOUND_COMMAND = (() => {
  switch (process.platform) {
    case "darwin":
      return "afplay /System/Library/Sounds/Glass.aiff"
    case "win32":
      return 'powershell -NoProfile -Command "[console]::beep(880,180)"'
    default:
      return 'if command -v paplay >/dev/null 2>&1; then paplay /usr/share/sounds/freedesktop/stereo/complete.oga; else printf "\\a"; fi'
  }
})()

const SOUND_COMMAND = process.env.OPENCODE_NOTIFY_SOUND_COMMAND?.trim() || DEFAULT_SOUND_COMMAND
const MIN_SOUND_GAP_MS = 750

const playSound = async (ctx: PluginInput, lastPlayedAt: { value: number }) => {
  const now = Date.now()
  if (now - lastPlayedAt.value < MIN_SOUND_GAP_MS) return

  lastPlayedAt.value = now
  await ctx.$`sh -lc ${SOUND_COMMAND}`.quiet().nothrow()
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
