import jenkins.*
import hudson.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.common.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import hudson.plugins.sshslaves.*;
import jenkins.model.*
import hudson.model.*
import hudson.security.*
import hudson.slaves.*
import hudson.plugins.sshslaves.verifiers.*

def instance = Jenkins.getInstance()
instance.setNumExecutors(0)

def bootstrap = new File("/var/jenkins_home/bootstrap").exists()

user = hudson.model.User.get('ciinabox', false)

if (user == null && !bootstrap) {
  println("no ciinabox user found...creating it")
  user = hudson.model.User.get('ciinabox')
  user.setFullName('ciinabox')
  email = new hudson.tasks.Mailer.UserProperty('ciinabox@base2services.com')
  user.addProperty(email)
  password = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword('ciinabox')
  user.addProperty(password)
  user.save()

  def realm = new HudsonPrivateSecurityRealm(false)
  instance.setSecurityRealm(realm)
  def strategy = new hudson.security.ProjectMatrixAuthorizationStrategy()
  strategy.add(Jenkins.ADMINISTER, "ciinabox")
  instance.setAuthorizationStrategy(strategy)
  instance.save()
} else {
  println("ciinabox user and default security already setup")
}


def creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
        com.cloudbees.plugins.credentials.common.StandardUsernameCredentials.class,
        Jenkins.instance,
        null,
        null
);

def jenkinsCreds = null
for (c in creds) {
  if (c.username == 'jenkins') {
    jenkinsCreds = c
    break
  }
}

if (jenkinsCreds == null) {
  global_domain = Domain.global()
  credentials_store =
          Jenkins.instance.getExtensionList(
                  'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
          )[0].getStore()
  jenkinsCreds = new UsernamePasswordCredentialsImpl(
          CredentialsScope.GLOBAL,
          null,
          "jenkins",
          "jenkins",
          "jenkins")
  credentials_store.addCredentials(global_domain, jenkinsCreds)
} else {
  println("jenkins creds already exists")
}

def envVars = [
        new EnvironmentVariablesNodeProperty.Entry('LANGUAGE', 'C.UTF-8'),
        new EnvironmentVariablesNodeProperty.Entry('LC_ALL', 'C.UTF-8')
]
envProps = new EnvironmentVariablesNodeProperty(envVars)

//add dind / dood slaves if they exist
int sshPort = 22

def createSlave = { String type ->
  String slaveName = "jenkins-docker-${type}-slave"
  try {
    //try to make connection on port 22
    Socket ssh = new Socket()
    //connect with timeout of 10s
    ssh.connect(new InetSocketAddress(slaveName, sshPort), 10000)
    boolean slaveExists = false
    for (jenkinsSlave in hudson.model.Hudson.instance.slaves) {
      if (jenkinsSlave.name.equals(slaveName)) {
        slaveExists = true
      }
    }

    println "Connection can be made to sshd on ${slaveName} host"

    if (slaveExists) {
      println "Jenkins ${slaveName} is already present on system"
    } else {
      println "Creating ${slaveName} ..."
      Jenkins.instance.addNode(new DumbSlave(slaveName,
              "Jenkins Docker ${type} Slave ",
              type.equals('dood') ? '/data/jenkins-dood' : "/home/jenkins",
              "8",
              Node.Mode.NORMAL,
              "docker docker-${type}",
              new SSHLauncher(
                      slaveName,     //host
                      22,            //port
                      jenkinsCreds,  //credentials
                      type.equals('dood') ? '-Djava.io.tmpdir=/data/jenkins-dood/tmp' : null,          //jvm opptions
                      null, //java path
                      null, //jdk installer
                      null, //prefix start cmd
                      null, //prefix end cmd
                      null, //launchTimeoutSeconds
                      null, //maxNumRetries
                      null, //retryWaitTime
                      new NonVerifyingKeyVerificationStrategy()
                      //verification strategy, running slave and host within same docker engine no need for verification
                      // ,
              ), new RetentionStrategy.Always(), [ envProps ]))
    }
  } catch (IOException ignored) {
    println "Connection can't be made to ${slaveName} host"
  }
}

createSlave('dind')
createSlave('dood')


if (!bootstrap) {
  println("touch /var/jenkins_home/bootstrap".execute().text)
} else {
  println("Bootstrap file present, this is not first execution of this file")
}

println "\nCIINABOX - Jenkins initialization complete at ${new java.util.Date()}\n"
