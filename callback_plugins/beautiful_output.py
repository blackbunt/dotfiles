# -*- coding: utf-8 -*-

# MIT License
#
# Copyright (c) 2019 Thiago Alves, modified by blackbunt
#
# removed AppKit releated stuff to work with my machine
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""A clean and opinionated output callback plugin.

The goal of this plugin is to consolidate Ansible's output in the style of
LINUX/UNIX startup logs, and use unicode symbols to display task status.

This Callback plugin is intended to be used on playbooks that you have
to execute *"in-person"*, since it does always output to the screen.

In order to use this Callback plugin, you should add this Role as a dependency
in your project, and set the ``stdout_callback`` option on the
:file:`ansible.cfg file::

    stdout_callback = beautiful_output

"""

# Make coding more python3-ish
from __future__ import absolute_import, division, print_function

__metaclass__ = type

DOCUMENTATION = """---
    callback: beautiful_output
    type: stdout
    author: Thiago Alves <thiago@rapinialves.com>
    short_description: a clean, condensed, and beautiful Ansible output
    version_added: 2.8
    description:
      - >-
        Consolidated Ansible output in the style of LINUX/UNIX startup
        logs, and use unicode symbols to organize tasks.
    extends_documentation_fragment:
      - default_callback
    requirements:
      - set as stdout in configuration
"""

import json
import locale
import os
import re
import textwrap
import yaml

from ansible import constants as C
from ansible import context
from ansible.executor.task_result import TaskResult
from ansible.module_utils._text import to_text, to_bytes
from ansible.module_utils.common._collections_compat import Mapping
from ansible.parsing.utils.yaml import from_yaml
from ansible.plugins.callback import CallbackBase
from ansible.template import Templar
from ansible.utils.color import colorize, hostcolor, stringc
from ansible.vars.clean import strip_internal_keys, module_response_deepcopy
from ansible.vars.hostvars import HostVarsVars
from collections import OrderedDict
from os.path import basename

# Entfernen der macOS-spezifischen Import- und Event-Handling-Teile
# Die Watchdog-Funktionalität wird ohne Bezug auf macOS als allgemeine Lösung beibehalten
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, EVENT_TYPE_CREATED

_symbol = {
    "success": to_text("✔"),
    "warning": to_text("⚠"),
    "failure": to_text("✘"),
    "dead": to_text("✝"),
    "yaml": to_text("🅨"),
    "retry": to_text("️↻"),
    "loop": to_text("∑"),
    "arrow_right": to_text("➞"),
    "skip": to_text("⤼"),
    "flag": to_text("⚑"),
}  # type: Dict[str,str]

# Farbcodes aus _color
_color = {
    "black": '\033[00;30m',
    "red": '\033[00;31m',
    "green": '\033[00;32m',
    "yellow": '\033[00;33m',
    "blue": '\033[00;34m',
    "purple": '\033[00;35m',
    "cyan": '\033[00;36m',
    "lightgray": '\033[00;37m',
    "lblack": '\033[01;30m',
    "lred": '\033[01;31m',
    "lgreen": '\033[01;32m',
    "lyellow": '\033[01;33m',
    "lblue": '\033[01;34m',
    "lpurple": '\033[01;35m',
    "lcyan": '\033[01;36m',
    "white": '\033[01;37m',
    "restore": '\033[0m',  # Zum Zurücksetzen der Farbe
}



_session_title = {
    "msg": "Message",
    "stdout": "Output",
    "stderr": "Error output",
    "module_stdout": "Module output",
    "module_stderr": "Module error output",
    "rc": "Return code",
    "changed": "Environment changed",
    "_ansible_no_log": "Omit logs",
    "use_stderr": "Use STDERR to output",
}  # type: Dict[str,str]

_session_order = OrderedDict(
    [
        ("_ansible_no_log", 3),
        ("use_stderr", 4),
        ("msg", 1),
        ("stdout", 1),
        ("module_stdout", 1),
        ("stderr", 1),
        ("module_stderr", 1),
        ("rc", 3),
        ("changed", 3),
    ]
)

ansi_escape = re.compile(
    r"""
    \x1B    # ESC
    [@-_]   # 7-bit C1 Fe
    [0-?]*  # Parameter bytes
    [ -/]*  # Intermediate bytes
    [@-~]   # Final byte
""",
    re.VERBOSE,
)

def symbol(key, color=None):  # type: (str, str) -> str
    output = _symbol.get(key, to_text(":{0}:").format(key))
    if not color:
        return output
    return stringc(output, color)

def iscollection(obj):
    """Helper method to check if a given object is not only a Squence, but also
    **not** any kind of string."""
    return isinstance(obj, Sequence) and not isinstance(obj, str)

def stringtruncate(value, color="normal", width=0, justfn=None, fillchar=" ", truncate_placeholder="[...]"):
    """Truncates a giving string using the configuration passed as arguments."""
    if not value:
        return fillchar * width

    if not justfn:
        justfn = str.rjust if isinstance(value, int) else str.ljust

    if isinstance(value, int):
        value = to_text("{:n}").format(value)

    truncsize = len(truncate_placeholder)
    do_not_trucate = len(value) <= width or width == 0
    truncated_width = width - truncsize

    return stringc(
        to_text(justfn(str(value), width))
        if do_not_trucate
        else to_text("{0}{1}".format(
            value[:truncated_width] if justfn == str.ljust else truncate_placeholder,
            truncate_placeholder if justfn == str.ljust else value[truncated_width:],
        )),
        color,
    )

def dictsum(totals, values):
    """Given two dictionaries of ``int`` values, this method will sum the value."""
    for key, value in values.items():
        if key not in totals:
            totals[key] = value
        else:
            totals[key] += value


class CallbackModule(CallbackBase):
    """The Callback plugin class to produce clean outputs."""
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "beautiful_output"

    def __init__(self, display=None):
        CallbackBase.__init__(self, display)
        self.delegated_vars = None
        self._item_processed = False
        self._current_play = None
        self._current_host = None
        self._task_name_buffer = None

    def display(self, msg, color=None, stderr=False):
        """Helper method to display text on the screen with optional color."""
        
        # Wenn eine Farbe angegeben ist, den Farbcodes aus _color anwenden
        if color and color in _color:
            msg = f"{_color[color]}{msg}{_color['restore']}"  # `restore` stellt die Standardfarbe wieder her.
        
        # Zeige die Nachricht auf dem Bildschirm an
        
        self._display.display(msg=msg, color=color, stderr=stderr, screen_only=True)
        
        # Entferne ANSI Escape-Sequenzen und gebe die Nachricht nur in Logs aus
        self._display.display(
            msg=ansi_escape.sub("", msg), stderr=stderr, log_only=True
        )

    def v2_playbook_on_start(self, playbook):
        """Displays the Playbook report Header when Ansible starts running it."""
        playbook_name = to_text("{0} {1}").format(
            symbol(to_text("yaml"), C.COLOR_HIGHLIGHT),
            stringc(basename(playbook._file_name), C.COLOR_HIGHLIGHT),
        )
        
        # Überprüfen, ob der Playbook im Check-Modus läuft
        if (
            "check" in context.CLIARGS
            and bool(context.CLIARGS["check"])
            and not self._is_run_verbose(verbosity=3)
            and not C.DISPLAY_ARGS_TO_STDOUT
        ):
            playbook_name = to_text("{0} (check mode)").format(playbook_name)

        self.display(to_text("\nExecuting playbook {0}").format(playbook_name))

        # Überprüfen, ob das Playbook mit hoher Verbosität ausgeführt wird
        if self._is_run_verbose(verbosity=3) or C.DISPLAY_ARGS_TO_STDOUT:
            self._display_cli_arguments()
        else:
            self._display_tag_strip(playbook)
        self.display(to_text("\n"))

    def _is_run_verbose(self, verbosity=0):
        """Check if the current run is verbose (should display information) 
        respecting the given verbosity level."""
        return context.CLIARGS.get('verbosity', 0) >= verbosity

    def _display_tag_strip(self, playbook, width=80):
        """Displays a line of tags present in the given ``playbook``.
        If the line is bigger than ``width`` characters, it will wrap the tag line before it crosses the threshold.
        
        Args:
            playbook (:obj:`~ansible.playbook.Playbook`): The playbook where to look for tags.
            width (int): How many characters can be used in a single line. Defaults to 80.
        """
        tags = self._get_tags(playbook)
        tag_strings = ""
        total_len = 0
        first_item = True
        for tag in sorted(tags):
            if not first_item:
                if total_len + len(tag) + 5 > width:
                    tag_strings += to_text("\n\n  {0} {1} {2} {3}").format(
                        "\x1b[6;30;47m", symbol("flag"), tag, "\x1b[0m"
                    )
                    total_len = len(tag) + 6
                    first_item = True
                else:
                    tag_strings += to_text(" {0} {1} {2} {3}").format(
                        "\x1b[6;30;47m", symbol("flag"), tag, "\x1b[0m"
                    )
                    total_len += len(tag) + 5
            else:
                first_item = False
                tag_strings += to_text("  {0} {1} {2} {3}").format(
                    "\x1b[6;30;47m", symbol("flag"), tag, "\x1b[0m"
                )
                total_len = len(tag) + 6
        self.display("\n")
        self.display(tag_strings)

    def _get_tags(self, playbook):
        """Returns a collection of tags that will be associated with all tasks
        running during this session.

        This means that it will collect all the tags available in the giving
        ``playbook``, and filter against the tags passed to Ansible in the
        command line.
        
        Args:
            playbook (:obj:`~ansible.playbook.Playbook`): The playbook where to
                look for tags.
        
        Returns:
            :obj:`list` of :obj:`str`: A sorted list of all tags used in this
            run.
        """
        tags = set()
        for play in playbook.get_plays():
            for block in play.compile():
                blocks = block.filter_tagged_tasks({})
                if blocks.has_tasks():
                    for task in blocks.block:
                        tags.update(task.tags)
        
        if "tags" in context.CLIARGS:
            requested_tags = set(context.CLIARGS["tags"])
        else:
            requested_tags = {"all"}
        
        if len(requested_tags) > 1 or next(iter(requested_tags)) != "all":
            tags = tags.intersection(requested_tags)
        
        return sorted(tags)

    def v2_runner_on_ok(self, result):
        """Displays the result of a task run."""
        """When a task completes successfully, show the 'OK' message."""
        task_name = result._task.get_name().strip()
        msg = "  [✓] {0}".format(task_name)
        print("\033[A", end="")  # Cursor zurück zum Anfang der Zeile bewegen
        # Zeige die neue Nachricht an
        self.display(msg, color=C.COLOR_OK)
        # Ausgabe von zusätzlichen Details zum Task
        #if result._result:
         #   self.display(json.dumps(result._result, indent=2))

    def v2_runner_on_failed(self, result, ignore_errors=False):
        """When a task fails, display the failure details."""
        print("\033[A", end="")  # Cursor zurück zum Anfang der Zeile bewegen
        # Zeige den Task-Namen und das Symbol [✘]
        task_name = result._task.get_name().strip()
        status = "ignored" if ignore_errors else "failed"
        msg = "  [✘] {0} - {1}".format(task_name, status)
        self.display(msg, color=C.COLOR_ERROR)
        if result._result:
            self.display(json.dumps(result._result, indent=2))

    def v2_runner_on_skipped(self, result):
        """Displays when a task is skipped."""
        print("\033[A", end="")  # Cursor zurück zum Anfang der Zeile bewegen
        # Zeige den Task-Namen und das Symbol [⤼]
        task_name = result._task.get_name().strip()
        msg = "  [⤼] {0}".format(task_name)
        self.display(msg, color=C.COLOR_SKIP)
    
    def v2_runner_on_unreachable(self, result):
        """Displays when a host becomes unreachable."""
        msg = "  %s Host unreachable." % symbol("dead")
        self.display(msg, color=C.COLOR_UNREACHABLE)

    def display_task_result(self, result, status, symbol_char="", indent=2):
        """Displays detailed output for a task's result."""
        task_name = result._task.get_name().strip()
        task_host = self._get_host_string(result)
        task_result = to_text("{0}{1} {2} [{3}]").format(
            " " * indent,
            symbol_char + " " if symbol_char else "",
            task_name,
            status.upper(),
        )

        # Zeige den Task-Namen und den Pfad (falls vorhanden)
        if 'path' in result._result:
            task_result += f"\n  Path: {result._result['path']}"
        if 'changed' in result._result:
            task_result += f"\n  Changed: {result._result['changed']}"

        self.display(task_result)

    def v2_playbook_on_no_hosts_matched(self):
        """Display a warning when there are no hosts available."""
        # Überprüfe, ob kein Inventar vorhanden ist, um die Warnung zu unterdrücken
        if not context.CLIARGS.get('inventory', None):
            return  # Verhindere die Anzeige der Warnung
        self.display(
            "  %s No hosts found!" % symbol("warning", "bright yellow"),
            color=C.COLOR_WARNING,
        )

    def v2_playbook_on_start(self, playbook):
        """Displays the Playbook report Header when Ansible starts running it."""
        
        # Überprüfen, ob kein Inventar angegeben wurde (um die Warnung zu unterdrücken)
        if not context.CLIARGS.get('inventory', None):
            # Keine Warnung anzeigen, wenn kein Inventar vorhanden ist
            return  # Stoppe die Ausgabe der Warnung
        
        playbook_name = to_text("{0} {1}").format(
            symbol(to_text("yaml"), C.COLOR_HIGHLIGHT),
            stringc(basename(playbook._file_name), C.COLOR_HIGHLIGHT),
        )
        self.display(to_text("\nExecuting playbook {0}").format(playbook_name))
    
    def v2_runner_on_start(self, *args, **kwargs):
        """Displays the task start information."""
        
        # Versuche, den Task aus kwargs zu extrahieren
        task = args[1] if len(args) > 1 else None
        if task:
            task_name = task.get_name().strip()
            msg = "  [➞] {0}".format(task_name)
            
            # Verwende eine benutzerdefinierte Farbe oder eine vorhandene Farbe
            self.display(msg, color=C.COLOR_SKIP) #color=_color["blue"])  # Beispiel: Gelb als Startfarbe
        else:
            # Fehlerausgabe, falls kein Task gefunden wird
            self.display("No task found in arguments", color=_color["red"])  # Beispiel: Rot bei Fehler








