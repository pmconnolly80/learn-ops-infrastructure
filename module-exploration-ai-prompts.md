# learn-ops-api: AI Prompts

## 1. Project structure

List all top-level directories in this project. For each one, explain what purpose it serves.
Then list the directories inside LearningAPI and explain what responsibility each one owns.

## 2. Dependencies

Open the Pipfile. Explain why this file exists and what it does.
Then find django, djangorestframework, and django-allauth. For each one, explain what functionality it provides and why this project uses it.

## 3. Decorators, serializers, and models

Open LearningAPI/decorators.py. What is a decorator and how is it used in this file?

Then open LearningAPI/serializers.py. What do serializers do? Why does a Django REST API need them? Explain how a serializer fits into the request/response cycle.

Then open the models folder inside LearningAPI. What is a Django model? Pick one model and explain what real-world thing it represents and why the API needs to track that data.

## 4. Views, viewsets, and the MTV pattern

Find one example of a plain view and one example of a viewset in this project. For each, show me the class name and file path.
Explain the difference between a view and a viewset and when you would choose one over the other.

Django uses a Model-Template-View pattern. This project has no HTML templates. What takes the template's role here, and why does that make sense for a REST API?