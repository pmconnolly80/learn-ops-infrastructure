# Trace Notes - Create a Student Note

## Request Path

| Layer | File | Class / Function | What it does |
|-------|------|-----------------|--------------|
| UI dialog | `learn-ops-client/src/components/dashboard/StudentNoteDialog.js` | `StudentNoteDialog` | Modal form where a coach types a note and selects a note type, then submits it |
| API helper | `learn-ops-client/src/components/utils/Fetch.js` | `fetchIt()` | Generic authenticated HTTP wrapper; `StudentNoteDialog` calls it with `POST /notes` and the note payload |
| URL router | `learn-ops-api/LearningPlatform/urls.py` | `router.register(r'notes', ...)` | DRF DefaultRouter maps `POST /notes` to `StudentNoteViewSet` |
| View | `learn-ops-api/LearningAPI/views/student_note_view.py` | `StudentNoteViewSet.create()` | Resolves student, coach, and note type FK lookups then saves a new `StudentNote` and returns HTTP 201 |
| Serializer | `learn-ops-api/LearningAPI/views/student_note_view.py` | `StudentNoteSerializer` | Converts the saved `StudentNote` model instance to JSON (`id`, `note`, `author`, `note_type`, `created_on`) |
| DB | `learn-ops-api/LearningAPI/models/people/student_note.py` | `StudentNote` | Django model with FKs to student, coach, and note type; stores the note text and auto-timestamps creation |
| UI refresh | `learn-ops-client/src/components/people/PeopleProvider.js` | `getStudentNotes()` | After the POST resolves, `StudentNoteDialog` calls this context function to re-fetch the notes list and update local state |

## Sequence Diagram

[Excalidraw link](https://excalidraw.com/#...)

![Diagram](./trace-diagram.png)