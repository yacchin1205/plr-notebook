import sys
import setuptools
from io import open

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="plrfs",
    version="0.0.1",
    author="Satoshi Yazawa",
    description="RPC client for PLRFS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/yacchin1205/plr-notebook/",
    packages=setuptools.find_packages(),
    install_requires=['aio-pika'],
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
    ],
    python_requires='>=3.6',
)
