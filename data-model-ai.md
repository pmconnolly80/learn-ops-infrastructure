# Data Model (AI)

## 1. Database Diagram

Mermaid diagrams are embedded directly in markdown using a fenced code block with the `mermaid` language tag:

USER

int

id

PK

string

username



Replace the example above with the diagram Claude generates:



## 2. Database Info

**Database type:** PostgreSQL 16

**ORM:** Django ORM (`django.db.backends.postgresql_psycopg2`) — configured in `LearningPlatform/settings.py`

## 3. Model to Table Mapping

Django builds table names automatically: `<app_label>_<modelname>` (all lowercase). The app label for this project is `learningapi`.

| Model Name | Table Name |
|------------|------------|
| `Book` | `learningapi_book` |
| `Course` | `learningapi_course` |
| `Capstone` | `learningapi_capstone` |
| `CapstoneTimeline` | `learningapi_capstonetimeline` |
| `CohortCourse` | `learningapi_cohortcourse` |
| `FoundationsLearnerProfile` | `learningapi_foundationslearnerprofile` |
| `FoundationsExercise` | `learningapi_foundationsexercise` |
| `LearningObjective` | `learningapi_learningobjective` |
| `LightningExercise` | `learningapi_lightningexercise` |
| `LightningTag` | `learningapi_lightningtag` |
| `ObjectiveTag` | `learningapi_objectivetag` |
| `Project` | `learningapi_project` |
| `ProjectNote` | `learningapi_projectnote` |
| `ProjectTag` | `learningapi_projecttag` |
| `ProposalStatus` | `learningapi_proposalstatus` |
| `StudentProject` | `learningapi_studentproject` |
| `TaxonomyLevel` | `learningapi_taxonomylevel` |
| `Assessment` | `learningapi_assessment` |
| `AssessmentObjective` | `learningapi_assessmentobjective` |
| `AssessmentWeight` | `learningapi_assessmentweight` |
| `Cohort` | `learningapi_cohort` |
| `CohortEvent` | `learningapi_cohortevent` |
| `CohortEventType` | `learningapi_cohorteventtype` |
| `CohortGithubProject` | `learningapi_cohortgithubproject` |
| `CohortInfo` | `learningapi_cohortinfo` |
| `GroupProjectRepository` | `learningapi_groupprojectrepository` |
| `NssUser` | `learningapi_nssuser` |
| `NssUserCohort` | `learningapi_nssusercohort` |
| `NSSUserTeam` | `learningapi_nssuserteam` |
| `OneOnOneNote` | `learningapi_oneonone_note` |
| `Opportunity` | `learningapi_opportunity` |
| `OpportunityUser` | `learningapi_opportunityuser` |
| `StudentAssessment` | `learningapi_studentassessment` |
| `StudentAssessmentStatus` | `learningapi_studentassessmentstatus` |
| `StudentMentor` | `learningapi_studentmentor` |
| `StudentNote` | `learningapi_studentnote` |
| `StudentNoteType` | `learningapi_studentnotetype` |
| `StudentPersonality` | `learningapi_studentpersonality` |
| `StudentTag` | `learningapi_studenttag` |
| `StudentTeam` | `learningapi_studentteam` |
| `CoreSkill` | `learningapi_coreskill` |
| `CoreSkillRecord` | `learningapi_coreskillrecord` |
| `CoreSkillRecordEntry` | `learningapi_coreskillrecordentry` |
| `LearningRecord` | `learningapi_learningrecord` |
| `LearningRecordEntry` | `learningapi_learningrecordentry` |
| `LearningWeight` | `learningapi_learningweight` |
| `Tag` | `learningapi_tag` |

### Example: `Book` model field mapping (`learningapi_book`)

| Python Field | SQL Column | Data Type |
|---|---|---|
| `id` | `id` | `SERIAL PRIMARY KEY` (auto-added by Django) |
| `name` | `name` | `VARCHAR(75)` |
| `course` | `course_id` | `INTEGER` (FK → `learningapi_course.id`) |
| `description` | `description` | `TEXT` |
| `index` | `index` | `INTEGER` |

> `projects` and `has_assessment` are Python `@property` methods — no corresponding columns; they query related tables at runtime.

## 4. Relationship Examples

**One-to-one** (field name: )

**One-to-many** (field name: )

**Many-to-many** (field name: )