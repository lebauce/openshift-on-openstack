"""
Code for building Origin
"""

import sys
import json
import os

from tito.common import (
    get_latest_tagged_version,
    check_tag_exists,
    get_spec_version_and_release
)

from tito.builder import Builder

class OpenshiftOnOpenstackBuilder(Builder):
    def _get_build_version(self):
        """
        Figure out the git tag and version-release we're building.
        """
        # Determine which package version we should build:
        build_version = None
        if self.build_tag:
            build_version = self.build_tag[len(self.project_name + "-"):]
        else:
            build_version = get_latest_tagged_version(self.project_name)
            if build_version is None:
                if not self.test:
                    error_out(["Unable to lookup latest package info.",
                            "Perhaps you need to tag first?"])
                sys.stderr.write("WARNING: unable to lookup latest package "
                    "tag, building untagged test project\n")
                build_version = get_spec_version_and_release(self.start_dir,
                    find_spec_file(in_dir=self.start_dir))
            self.build_tag = "v{0}".format(build_version)

        if not self.test:
            check_tag_exists(self.build_tag, offline=self.offline)
        return build_version

# vim:expandtab:autoindent:tabstop=4:shiftwidth=4:filetype=python:textwidth=0:
