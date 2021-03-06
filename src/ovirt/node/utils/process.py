#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# process.py - Copyright (C) 2012 Red Hat, Inc.
# Written by Fabian Deutsch <fabiand@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.
from subprocess import STDOUT, PIPE
import logging
import subprocess
import sys

"""
Some convenience functions related to processes
"""


LOGGER = logging.getLogger(__name__)

COMMON_POPEN_ARGS = {
    "close_fds": True
}

CalledProcessError = subprocess.CalledProcessError


def __update_kwargs(kwargs):
    new_kwargs = dict(COMMON_POPEN_ARGS)
    new_kwargs.update(kwargs)
    return new_kwargs


def __check_for_problems(args, kwargs):
    if ("shell" in kwargs) and (args and type(args[0]) is list):
        raise RuntimeError("Combining  shell=True and a command list does " +
                           "not work. With shell=True the first argument" +
                           "must be a string. A list otherwise.")


def popen(*args, **kwargs):
    """subprocess.Popen wrapper to not leak file descriptors
    """
    kwargs = __update_kwargs(kwargs)
    LOGGER.debug("Popen with: %s %s" % (args, kwargs))
    # Intentionally no check for common problems
    return subprocess.Popen(*args, **kwargs)


def call(*args, **kwargs):
    """subprocess.call wrapper to not leak file descriptors
    """
    kwargs = __update_kwargs(kwargs)
    LOGGER.debug("Calling with: %s %s" % (args, kwargs))
    __check_for_problems(args, kwargs)
    return int(subprocess.call(*args, **kwargs))


def check_call(*args, **kwargs):
    """subprocess.check_call wrapper to not leak file descriptors
    """
    kwargs = __update_kwargs(kwargs)
    LOGGER.debug("Checking call with: %s %s" % (args, kwargs))
    __check_for_problems(args, kwargs)
    return int(subprocess.check_call(*args, **kwargs))


def check_output(*args, **kwargs):
    """subprocess.check_output wrapper to not leak file descriptors
    """
    kwargs = __update_kwargs(kwargs)
    LOGGER.debug("Checking output with: %s %s" % (args, kwargs))
    __check_for_problems(args, kwargs)
    try:
        return unicode(subprocess.check_output(*args, **kwargs),
                       encoding=sys.stdin.encoding or "utf-8")
    except AttributeError:
        # We're probably on Python 2.7, which doesn't have check_output
        # http://docs.python.org/2.6/library/subprocess.html#module-subprocess
        # Working around by using pipe, which doesn't check, but returns the
        # output
        return pipe(*args, **kwargs)


def pipe(cmd, stdin=None, **kwargs):
    """Run a non-interactive command and return it's output

    Args:
        cmd: Cmdline to be run
        stdin: (optional) Data passed to stdin

    Returns:
        stdout, stderr of the process (as one blob)
    """
    kwargs.update({"stdin": PIPE,
                   "stdout": PIPE,
                   "stderr": STDOUT})
    __check_for_problems(cmd, kwargs)
    return unicode(popen(cmd, **kwargs).communicate(stdin)[0])
