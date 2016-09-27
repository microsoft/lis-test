#!/usr/bin/env python

try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup

VERSION = '1.0'

long_description = '''lisa-parser is an utility for the
LIS Automation framework used for parsing test runs
and inserting the results in a database'''

setup(
    name='lisa-parser',
    version=VERSION,
    description='Parsing utility for LISA',
    long_description=long_description,
    license='Apache',
    packages=['lisa_parser']
)
