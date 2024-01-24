#!/usr/bin/env python3
from setuptools import setup, find_packages

setup(
    name='OpenFinchServer',
    version='0.1',
    packages=find_packages(),
    install_requires=[
        'aiohttp',
		'dataclasses',
		'pillow',
		'screeninfo',
		'setuptools',
		'asyncio',
		'opencv-python',
		'numpy',
		'pigpio',
		'requests',
		'statistics',
		'v4l2py'
    ],
    # entry_points={
    #     'console_scripts': [
    #         'openfinchserver = OpenFinchServer.main:main',
    #     ],
    # },
)