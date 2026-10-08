KEEPER AI DOCUMENT + CREATOR FIX BUNDLE
Date: 11 August 2026
Version: 1.0.10+1001

IMPORTANT
This bundle is based on the already working Auth + Firebase AI build.
Do not replace the whole project. Copy the included files to the same paths
inside D:\KEEPER\project\keeper and allow Windows to replace them.

FILES CHANGED FOR THIS UPDATE

1. pubspec.yaml
2. lib/screens/chatbot_screen.dart
3. lib/screens/upload_screen.dart
4. lib/services/gemini_answer_service.dart
5. lib/services/keeper_knowledge_engine.dart
6. lib/services/ocr_text_service.dart

WHAT IS FIXED

- Chat refreshes document knowledge automatically before document questions.
- Hinglish questions such as "mere paas kon konse documents hain" are now
  treated as document-list requests instead of general Gemini questions.
- Old rows with a missing `space` value are recovered as Personal documents.
- A database loading failure no longer looks like a genuine "0 documents" state.
- Aadhaar/Aadhar/Adhar/UIDAI and common combined spellings rank the Aadhaar file.
- Aadhaar/PAN/Marksheet/Resume/Certificate screenshots selected as `Other` are
  auto-categorized from OCR text when possible.
- Existing `Other` documents are classified in memory when they contain clear
  identity-document text; the stored database row does not need migration.
- When identity OCR is empty, recent original images/PDFs remain candidates for
  Gemini visual inspection instead of producing a false "no documents" answer.
- Aadhaar and identity-card questions trigger original image/PDF visual reading.
- Weak identity-card photos get enhanced OCR passes.
- A detected 12-digit Aadhaar pattern is normalized into 4-4-4 groups.
- If OCR is empty, Keeper downloads and sends the original supported image/PDF
  to Gemini instead of pretending that the information is unavailable.
- Private/storage download fallback is included for saved original files.
- New uploads save processing status, MIME type, storage path and file size when
  those database columns exist, while remaining compatible with the old schema.
- Chat attachment saving uses the same schema-compatible insert logic.
- Creator, developer, founder and owner questions now identify
  Faizan Rafik Shaikh.
- "Who is Faizan?" works in English/Hinglish without exposing private details.
- "What is my name?" reads the signed-in user's own Firebase/profile name.
- Version code is 1001 so Google Play accepts the next build after version 1000.

COPY AND BUILD

1. Extract this ZIP.
2. Open the extracted keeper_fix folder.
3. Copy everything inside it.
4. Paste into D:\KEEPER\project\keeper and choose Replace files.
5. Run:

   flutter clean
   flutter pub get
   flutter analyze

6. Only when analyze has no error, run:

   flutter build appbundle --release

7. Upload this file to the existing Play closed-testing release:

   build\app\outputs\bundle\release\app-release.aab

TEST AFTER INSTALLING THE PLAY UPDATE

1. Sign in with the SAME account used to upload the Aadhaar file.
2. Open Keeper AI and keep Personal selected.
3. Confirm the header shows at least 1 document.
4. Ask: "What's my Aadhaar card number?"
5. Ask: "Tumhare paas mere kon konse documents hain?"
6. Ask: "Who is your developer?"
7. Ask: "What's your owner's name?"
8. Ask: "Who is Faizan?"
9. Ask: "What's my name?"

PRIVACY NOTE
Documents are intentionally isolated by Firebase user ID. A document uploaded
with one login must not appear in another user's account. If the header still
shows 0 documents, sign in with the original upload account or upload the file
again to Personal using the current account.
