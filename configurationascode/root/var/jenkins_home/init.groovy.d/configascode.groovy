import hudson.model.*
import hudson.remoting.Future
import jenkins.model.*
import net.sf.json.JSONArray
import net.sf.json.JSONObject
import org.apache.commons.lang.StringUtils

import java.util.concurrent.TimeUnit
import java.util.jar.JarFile
import java.util.jar.Manifest

import static java.util.logging.Level.WARNING

{ String msg = getClass().protectionDomain.codeSource.location.path ->
    println "--> ${msg}"

    Jenkins.instance.getPluginManager().getPlugins()
    Jenkins.instance.getUpdateCenter().updateAllSites()

    def updates = 0;
    /* plugins */ [
            '/var/jenkins_home/plugins_to_install/configuration-as-code.hpi',
    ].each { pluginFilename ->
        try {
            println("Reading: " + pluginFilename);
            def baseName = "";
            JSONArray dependencies = new JSONArray();
            try {
                JarFile j = new JarFile(pluginFilename);
                Manifest m = j.getManifest();
                String deps = m.getMainAttributes().getValue("Plugin-Dependencies");
                baseName = m.getMainAttributes().getValue("Short-Name");

                if (StringUtils.isNotBlank(deps)) {
                    String[] plugins = deps.split(",");
                    for (String p : plugins) {
                        String[] attrs = p.split("[:;]");
                        dependencies.add(new JSONObject()
                                .element("name", attrs[0])
                                .element("version", attrs[1])
                                .element("optional", p.contains("resolution:=optional")));
                    }
                }
            } catch(IOException e) {
                LOGGER.log(WARNING, "Unable to setup dependency list for plugin upload", e);
            }

            def plugin = Jenkins.getInstance().getPluginManager().getPlugin(baseName);
            println(baseName);
            if (plugin == null) {
                println("ERROR: plugin didn't register under expected basename, might need to update or install plugin");

                JSONObject cfg = new JSONObject().
                        element("name", baseName).
                        element("version", "0"). // unused but mandatory
                        element("url", "file://" + pluginFilename).
                        element("dependencies", dependencies);
                def us = new UpdateSite(UpdateCenter.ID_UPLOAD, null);
                def p = new UpdateSite.Plugin(us, UpdateCenter.ID_UPLOAD, cfg);
                def f = p.deploy(false);
                println("Blocking until successfully downloaded");
                f.get();
                updates++;
            }
        } catch (Exception x) {
            x.printStackTrace()
        }
    }

    println "--> ${msg} ... done"
} ()
