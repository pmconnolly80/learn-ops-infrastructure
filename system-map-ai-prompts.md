# System Map AI Prompts

## 1. Describe the System

prompt1:
Draw the system architecture of this system. Find every service and every connection between them. For each connection note the direction and type (HTTP, database query, pub/sub event, etc.) port number and frameworks like React, Django etc should be labeled.
Output as ASCII art diagram. Each service gets its own labeled box. Every dependency between services gets a directional arrow labeled with the connection type. Do not add anything beyond services and their connections.

prompt2:
Add diagram to your memory.

## 2. Convert to a Mermaid Diagram

prompt1:
Check your memory for the system diagram. Convert it to Mermaid. Use graph LR.
Rules:
- Each service is a node with a short label
- Each connection is a directed edge
- Label every edge with the connection type (HTTP, DB, pub/sub, etc.) and port if known
- Do not add anything beyond services and their connections
Output only the Mermaid code block.

