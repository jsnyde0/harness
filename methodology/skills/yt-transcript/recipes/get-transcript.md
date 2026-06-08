# Recipe: Get YouTube Transcript

**When to use:** User provides a YouTube URL or video ID and wants the transcript/captions.

## Steps

### 1. Extract the video ID

From URL patterns:
- `https://www.youtube.com/watch?v=<ID>` → ID is the `v=` value
- `https://youtu.be/<ID>` → ID is the path segment
- `https://www.youtube.com/shorts/<ID>` → ID is the path segment

### 2. Try Method 1 (youtube-transcript-api)

```bash
uvx --from youtube-transcript-api youtube_transcript_api --languages en --format text <VIDEO_ID>
```

`--languages en` requests English specifically. If the video only has non-English captions, this will fail — that's intentional, it routes to Method 2's language-handling logic.

**Success:** Non-empty text output with no error messages → go to step 4.

**Failure:** Any of the following → go to step 3:
- Any error text in output (e.g. `CouldNotRetrieveTranscript`, `NoTranscriptFound`, `TranscriptsDisabled`, `VideoUnavailable`)
- Empty output

Note: Music video transcripts may contain `♪` symbols — expected, not an error.

### 3. Fallback — yt-dlp subtitles

```bash
mkdir -p ~/tmp
yt-dlp --write-auto-subs --write-subs --sub-langs en --skip-download --output "~/tmp/%(id)s" "https://www.youtube.com/watch?v=<VIDEO_ID>"
```

Output file will be at `~/tmp/<VIDEO_ID>.en.vtt` or `~/tmp/<VIDEO_ID>.en.srt`.

**If `.en.vtt`/`.en.srt` found:** Strip timing markup (lines with `-->`, timestamp headers, blank lines between cues) and read the text. → go to step 4.

**If only non-English subtitle files found:** Ask the user:
> "This video has captions in [language(s)] but not English. Want me to use [language]?"
Then re-run with `--sub-langs <lang>` if they confirm.

**If no subtitle file of any kind:** Inform the user:
> "This video has no auto-captions. I can download the audio and transcribe it with Whisper using the `small` model (~5-10 min for a long video). Shall I proceed?"

Only proceed to Whisper with explicit user confirmation — it's slow and downloads audio.

**Whisper command (only after confirmation):**
```bash
mkdir -p ~/tmp
yt-dlp --extract-audio --audio-format mp3 --output "~/tmp/%(id)s.%(ext)s" "https://www.youtube.com/watch?v=<VIDEO_ID>"
uvx --from openai-whisper whisper ~/tmp/<VIDEO_ID>.mp3 --model small --output_format txt --output_dir ~/tmp/
```

### 4. Save and present

**Always save the cleaned transcript** to `~/tmp/<VIDEO_ID>_transcript.md` first. For Method 1 output, use the Write tool. For Method 2, strip VTT/SRT markup (lines with `-->`, timestamp headers, blank lines between cues) and Write the cleaned text. For Method 3, the Whisper `.txt` output can be moved/renamed to `.md`.

**Default: provide a summary** grounded in the saved transcript. Read from the saved file when summarizing — do not paraphrase from prior knowledge of the video.

For short transcripts (~300 words is a reasonable cutoff — use judgment), quote the transcript inline instead — that often IS the most natural summary.

Only paste the full transcript verbatim when the user explicitly asks for it.

Always tell the user which method succeeded AND the saved file path:
- Method 1: "Retrieved via Method 1 (youtube-transcript-api). Saved to `~/tmp/<VIDEO_ID>_transcript.md`."
- Method 2: "Retrieved via Method 2 (yt-dlp subtitles). Saved to `~/tmp/<VIDEO_ID>_transcript.md`."
- Method 3: "Retrieved via Method 3 (Whisper transcription). Saved to `~/tmp/<VIDEO_ID>_transcript.md`."

Offer follow-ups: "Want the full text inline?" or "Specific questions about it?"
