require "open3"
require "tmpdir"
require "fileutils"
require "timeout"
require "uri"

prefix = File.expand_path(ARGV.fetch(0))
modules = "#{prefix}/libexec/openldap"
schema = "#{prefix}/share/openldap/schema"
# Preflight source builds supply the same schema set separately.
schema = ENV.fetch("LDAP_SMOKE_SCHEMA", schema)
def command(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{File.basename(args.first)} failed (#{status.exitstatus}): #{err}" unless status.success?
  out
end
Dir.mktmpdir("ldap-tap-", "/tmp") do |dir|
  FileUtils.mkdir("#{dir}/db", mode: 0700)
  socket = "#{dir}/socket"
  uri = "ldapi://" + socket.gsub("/", "%2F")
  base = "dc=example,dc=org"
  admin = "cn=admin,#{base}"
  user = "uid=fixture,#{base}"
  sha = command("#{prefix}/sbin/slappasswd", "-o", "module-path=#{modules}", "-o", "module-load=pw-sha2", "-h", "{SSHA512}", "-s", "fixture-initial") .strip
  argon = command("#{prefix}/sbin/slappasswd", "-o", "module-path=#{modules}", "-o", "module-load=argon2", "-h", "{ARGON2}", "-s", "fixture-argon").strip
  raise "SSHA512 unavailable" unless sha.start_with?("{SSHA512}")
  raise "Argon2id unavailable" unless argon.start_with?("{ARGON2}$argon2id$")
  File.write("#{dir}/slapd.conf", <<~CONF)
    include #{schema}/core.schema
    include #{schema}/cosine.schema
    include #{schema}/inetorgperson.schema
    pidfile #{dir}/slapd.pid
    argsfile #{dir}/slapd.args
    modulepath #{modules}
    moduleload pw-sha2
    moduleload argon2
    password-hash {SSHA512}
    authz-regexp "^gidNumber=#{Process.gid}[+]uidNumber=#{Process.uid},cn=peercred,cn=external,cn=auth$" "#{admin}"
    database mdb
    maxsize 16777216
    suffix "#{base}"
    rootdn "#{admin}"
    rootpw fixture-admin
    directory #{dir}/db
    access to attrs=userPassword by self write by anonymous auth by * none
    access to * by users read by * none
  CONF
  File.write("#{dir}/seed.ldif", <<~LDIF)
    dn: #{base}
    objectClass: domain
    dc: example

    dn: #{user}
    objectClass: inetOrgPerson
    uid: fixture
    cn: Fixture
    sn: Test
    userPassword: #{sha}

    dn: uid=argon,#{base}
    objectClass: inetOrgPerson
    uid: argon
    cn: Argon
    sn: Test
    userPassword: #{argon}
  LDIF
  command("#{prefix}/sbin/slapadd", "-f", "#{dir}/slapd.conf", "-l", "#{dir}/seed.ldif")
  pid = Process.spawn("#{prefix}/libexec/slapd", "-d", "0", "-f", "#{dir}/slapd.conf", "-h", uri, out: "#{dir}/server.log", err: [:child, :out])
  begin
    ldap = ["-H", uri]
    who = "#{prefix}/bin/ldapwhoami"
    # The socket inode appears before slapd starts accepting connections.
    Timeout.timeout(30) do
      loop do
        out, _, status = Open3.capture3(who, *ldap, "-Q", "-Y", "EXTERNAL")
        if status.success?
          raise "EXTERNAL mapping failed" unless out.include?(admin)
          break
        end
        raise "Test server exited: #{File.read("#{dir}/server.log")}" if Process.waitpid(pid, Process::WNOHANG)
        sleep 0.1
      end
    end
    command(who, *ldap, "-x", "-D", user, "-w", "fixture-initial")
    command(who, *ldap, "-x", "-D", "uid=argon,#{base}", "-w", "fixture-argon")
    command("#{prefix}/bin/ldappasswd", *ldap, "-x", "-D", admin, "-w", "fixture-admin", "-s", "fixture-changed", user)
    out = command("#{prefix}/bin/ldapsearch", *ldap, "-LLL", "-o", "ldif-wrap=no", "-x", "-D", admin, "-w", "fixture-admin", "-b", user, "-s", "base", "userPassword")
    encoded = out.lines.find { |l| l.start_with?("userPassword:: ") }
    value = encoded ? encoded.split(":: ", 2).last.unpack1("m") : out.lines.find { |l| l.start_with?("userPassword: ") }.to_s.split(": ", 2).last.to_s
    raise "RFC3062 did not generate SSHA512" unless value.start_with?("{SSHA512}")
    command(who, *ldap, "-x", "-D", user, "-w", "fixture-changed")
    _, _, bad = Open3.capture3(who, *ldap, "-x", "-D", user, "-w", "fixture-initial")
    raise "Old password accepted" if bad.success?
    puts "PASS: SSHA512, Argon2id, RFC3062 SSHA512 default, rejected old password, LDAPI EXTERNAL"
  ensure
    Process.kill("TERM", pid) rescue Errno::ESRCH
    Process.wait(pid) rescue Errno::ECHILD
  end
end
