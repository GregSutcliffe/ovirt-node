#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# plugins_page.py - Copyright (C) 2013 Red Hat, Inc.
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
from ovirt.node import ui
from ovirt.node.plugins import NodePlugin
from ovirt.node.utils import process
import glob
import os
import re
from subprocess import CalledProcessError

"""
A plugin for a plugins page
"""


class Plugin(NodePlugin):
    def __init__(self, app):
        super(Plugin, self).__init__(app)
        self._model = {}

    def name(self):
        return _("Plugins")

    def rank(self):
        return 300

    def ui_content(self):
        all_plugins = self.__list_of_plugins()
        if all_plugins:
            selected_plugin = all_plugins[0][0]
            ws = [ui.Header("header[0]", _("Installed Plugins")),

                  ui.Table("plugins.installed", "", _("Installed plugins:"),
                           all_plugins, selected_plugin),

                  ui.Divider("divider[0]"),

                  ui.Row("row[0]", [ui.Label("label[0]", _("Name:")),
                                    ui.Label("plugin.name", "")]),

                  ui.Row("row[1]", [ui.Label("label[0]", _("Version:")),
                                    ui.Label("plugin.version", "")]),

                  ui.Row("row[2]", [ui.Label("label[0]", _("Date installed:")),
                                    ui.Label("plugin.createdat", "")]),

                  ui.Divider("divider[1]"),

                  ui.Row("row[3]", [ui.SaveButton("button.drpm",
                                                  _("RPM Diff")),
                                    ui.SaveButton("button.dsrpm",
                                                  _("SRPM Diff")),
                                    ui.SaveButton("button.dfile",
                                                  _("File Diff"))])
                  ]
        else:
            ws = [ui.Header("header[0]", _("Plugins")),
                  ui.Label("label[0]",
                           _("There are no plugins currently installed"))]

        page = ui.Page("page", ws)
        page.buttons = []
        self.widgets.add(page)
        return page

    def model(self):
        return {}

    def validators(self):
        return {}

    def on_change(self, changes):
        if "plugins.installed" in changes:
            all_plugins = self.get_plugins_list()
            self.logger.debug("Using plugins: %s" % all_plugins)
            name = changes["plugins.installed"]
            version, createdat = all_plugins[name]
            self.widgets["plugin.name"].text(name)
            self.widgets["plugin.version"].text(version)
            self.widgets["plugin.createdat"].text(createdat)
            self._model["plugin"] = name

    def on_merge(self, changes):
        p_manifests_dir = "/etc/ovirt-plugins-manifests.d"
        fn = None
        if "button.drpm" in changes:
            fn = glob.glob("%s/delta-manifest-rpm.txt" %
                           (p_manifests_dir))[0]
        elif "button.dsrpm" in changes:
            fn = glob.glob("%s/delta-manifest-srpm.txt" %
                           (p_manifests_dir))[0]
        elif "button.dfile" in changes:
            fn = glob.glob("%s/delta-manifest-file.txt" %
                           (p_manifests_dir))[0]

        if fn:
            self.logger.debug("Reading manifest from: %s" % fn)
            with open(fn) as src:
                contents = src.read()
            return ui.TextViewDialog("output.dialog", "Manifest",
                                     contents)

    def __list_of_plugins(self):
        sp = sorted(self.get_plugins_list().items())
        return [(k, "%s (%s)" % (k, v[0])) for k, v in sp]

    def get_plugins_list(self):
        plugin_dict = {}
        plugin_dir = "/etc/ovirt-plugins.d/"
        if os.path.exists(plugin_dir):
            for f in os.listdir(plugin_dir):
                if not f.endswith(".minimize"):
                    with open(plugin_dir + f) as p:
                        if re.compile(r'Name:.*?\nVer.*:.*?\nInstall Date:.*',
                                      re.M | re.S).match(open(plugin_dir + f
                                                              ).read()):
                            #Hopefully a plugin metadata file
                            lines = p.readlines()
                            name = lines[0].strip().split(":")[1]
                            ver = lines[1].strip().split(":")[1]
                            install_date = lines[2].strip().replace(
                                "Install Date:", "")
                        else:
                            try:
                                cmd = '/bin/rpm -qf %s/%s --qf %%{name}' % \
                                    (plugin_dir, f)
                                package = process.check_output(cmd.split(' ')
                                                               ).strip()
                                cmd = "rpm -q %s --qf 'NAME: %s DATE: \
                                       %%{version}-%%{release}.%%{arch} INST: \
                                       %%{INSTALLTIME:date}\\n'" %\
                                    (package, package)
                                name, ver, install_date = re.match(
                                    r'NAME: (.*?) DATE: (.*?) INST: (.*)',
                                    process.check_output(cmd, shell=True
                                                         ).strip()).groups()
                            except CalledProcessError:
                                continue

                    plugin_dict[name] = (ver, install_date)
        return plugin_dict
