import argparse
import os
import signal
import sys

from faster_whisper import WhisperModel


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe audio files using Whisper AI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  transcriber audio.mp3
  transcriber audio.mp3 --language es --model medium
  transcriber audio.mp3 --output transcript.txt
        """,
    )

    parser.add_argument("audio_file", help="Path to the audio file to transcribe")

    parser.add_argument("-l", "--language", default="en", help="Language code (default: en)")

    parser.add_argument(
        "-m",
        "--model",
        default="small",
        choices=["tiny", "base", "small", "medium", "large"],
        help="Whisper model size (default: small)",
    )

    parser.add_argument("-o", "--output", help="Output file path (default: <audio_file>.txt)")

    args = parser.parse_args()

    audio_path = args.audio_file

    if not os.path.exists(audio_path):
        print(f"Error: File not found: {audio_path}")
        sys.exit(1)

    output_path = args.output or (os.path.splitext(audio_path)[0] + ".txt")

    print(f"Transcribing: {audio_path}")
    print(f"Language: {args.language}")
    print(f"Model: {args.model}")
    print(f"Output: {output_path}")
    print()

    model = WhisperModel(args.model, device="auto", compute_type="int8")

    stop_flag = {"stopped": False}

    def handle_interrupt(sig, frame):
        stop_flag["stopped"] = True
        print("\nInterrupted. Partial output saved.")
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_interrupt)

    with open(output_path, "w", encoding="utf-8") as f:
        try:
            segments, _info = model.transcribe(audio_path, language=args.language)
            for segment in segments:
                if stop_flag["stopped"]:
                    break
                text = segment.text.strip()
                print(text)
                f.write(text + "\n")
                f.flush()
        except KeyboardInterrupt:
            print("\nTranscription interrupted. Partial output saved.")
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)
        finally:
            print(f"\nOutput saved to: {output_path}")


if __name__ == "__main__":
    main()
