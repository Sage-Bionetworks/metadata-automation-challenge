FROM python:3.7

RUN pip install jsonschema click

COPY schema/output-schema.json /output-schema.json
COPY schema/validate.py /usr/local/bin/validate.py
