---
name: yt-transcript
description: >
  Get the transcript of a YouTube video. Use when the user provides a YouTube URL or video ID
  and wants the transcript, captions, subtitles, or spoken content. Trigger phrases: "transcript
  of this video", "what does this video say", "get me the captions", "summarize this YouTube video",
  "transcribe this YouTube video". Do NOT use for downloading video/audio files — this is
  transcript-only.
version: 1.0.0
---

# YouTube Transcript Skill

Extracts transcripts from YouTube videos. Uses the lightest approach that works — no audio
download unless absolutely necessary.

## Method Hierarchy

Try methods in order. Stop at the first one that succeeds.

**Method 1 — youtube-transcript-api (fastest, no download)**
Works on ~95% of videos that have auto-generated or manual captions. Zero audio download.

```bash
uvx --from youtube-transcript-api youtube_transcript_api --languages en --format text <VIDEO_ID>
```

- Extract video ID from URL: `https://www.youtube.com/watch?v=<VIDEO_ID>` or `https://youtu.be/<VIDEO_ID>`
- `--languages en` requests English specifically; if the video only has non-English captions this will fail with a language error — that's correct, it triggers the non-English handling in Method 2
- Outputs clean plain text transcript
- **Failure detection:** Any error text in the tool output (e.g. `CouldNotRetrieveTranscript`, `NoTranscriptFound`, `TranscriptsDisabled`, `VideoUnavailable`, network errors) → treat as failure, try Method 2. Empty output also counts as failure.
- **Music videos:** Auto-captions for music videos include `♪` symbols — this is expected, not an error

**Method 2 — yt-dlp subtitles (no audio download)**
Use when Method 1 fails for any reason.

```bash
yt-dlp --write-auto-subs --write-subs --sub-langs en --skip-download --output "~/tmp/%(id)s" "<FULL_URL>"
```

Output file will be at `~/tmp/<VIDEO_ID>.en.vtt` or `~/tmp/<VIDEO_ID>.en.srt`. Strip timing markup and read text content.

- **Non-English videos:** If no `.en.vtt` is produced but other language files appear (e.g. `.fr.vtt`), ask the user which language to use, then re-run with `--sub-langs <lang>`
- **Failure detection:** No subtitle file of any kind → video has no captions → offer Method 3

**Method 3 — yt-dlp + Whisper (last resort, slow)**
Use only when the video genuinely has no captions. Requires explicit user confirmation first.

```bash
# Download audio only
yt-dlp --extract-audio --audio-format mp3 --output "~/tmp/%(id)s.%(ext)s" "<FULL_URL>"

# Transcribe with Whisper — use 'small' model (best speed/accuracy balance)
uvx --from openai-whisper whisper ~/tmp/<VIDEO_ID>.mp3 --model small --output_format txt --output_dir ~/tmp/
```

`base` model is faster but less accurate. `medium`/`large` are more accurate but slow.

## Decision Rules

- Always try Method 1 first — it's instant and works on the vast majority of videos
- Method 1: any error or non-zero exit → try Method 2 (don't stop at `CouldNotRetrieveTranscript` alone)
- Method 2: no subtitle file of any language → fall back to Method 3 with user confirmation
- Method 2: subtitle file in wrong language → ask user, re-run with correct `--sub-langs`
- Method 3: only with explicit user confirmation ("yes, proceed" or similar)
- Always tell the user which method succeeded, e.g. "Retrieved via Method 1 (youtube-transcript-api)"

## Output Handling

**Always save the retrieved transcript** to `~/tmp/<VIDEO_ID>_transcript.md`. Tell the user the file path. This gives them a canonical copy to re-read, grep, or copy from regardless of how it's presented in chat.

**Default presentation: summarize.** Provide a concise summary grounded in the retrieved transcript. Read from the saved file when summarizing — do not paraphrase from prior knowledge of the video. Music-video lyrics with `♪` markers are part of the transcript; preserve them when quoting.

For short transcripts (~300 words is a reasonable cutoff — use judgment), quoting the transcript inline often IS the most natural summary. Do that when it serves the user better.

Only skip the summary and paste verbatim when the user explicitly asks ("give me the raw transcript", "paste the full text"). The saved file remains the canonical copy.

After presenting, offer follow-ups (e.g. "want the full text inline?" or "specific questions about it?").

## Recipes

- `recipes/get-transcript.md` — Standard transcript retrieval workflow
