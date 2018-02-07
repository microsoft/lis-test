# JSON Parser Guide

### Introduction
This README is intended as a guide for running JSON Parser (parser.py). This is a python script that will push the contents of a JSON file to a specific database.

### Usage
- Requirements: Python 2.7, pyodbc<=3.0.10, envparse<=0.2.0
- parser.py will need 2 files:
  + tests.json - this contains the data that will be insterted into the database. A sample file is provided inside this folder.
  + db.config - database config file that contains necessary info (user, password, table name, etc)
- once these 2 files are available inside the same folder as parser.py, we can simply run 'python.exe parser.py' and the JSON entries will be added to the database