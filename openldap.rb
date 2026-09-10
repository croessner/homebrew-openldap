# Based on Homebrew/homebrew-core's OpenLDAP formula (BSD-2-Clause).
class Openldap < Formula
  desc "OpenLDAP with SSHA512 password defaults and optional Argon2id support"
  homepage "https://www.openldap.org/software/"
  url "https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.7.1.tgz"
  sha256 "253db80f301258ea69cda1184766d57395b836aaabf41157eb0316eb0fac1341"
  license "OLDAP-2.8"

  keg_only :provided_by_macos

  depends_on :macos
  depends_on "argon2"
  depends_on "libtool"
  depends_on "openssl@3"
  on_macos do
    depends_on "llvm@22" => :build
  end
  uses_from_macos "mandoc" => :build
  uses_from_macos "cyrus-sasl"

  livecheck do
    url "https://www.openldap.org/software/download/"
    regex(/Feature Release.*?OpenLDAP[ -](\d+\.\d+\.\d+)/im)
  end

  def install
    if OS.mac?
      ENV["CC"] = Formula["llvm@22"].opt_bin/"clang"
      ENV["CXX"] = Formula["llvm@22"].opt_bin/"clang++"
      # Upstream libtool recognizes 10.x but also needs modern macOS versions.
      inreplace "configure", "\t10.*)", "\t*)"
    end
    args = %W[
      --prefix=#{prefix}
      --sysconfdir=#{etc}
      --localstatedir=#{var}
      --enable-modules
      --enable-argon2
      --with-argon2=libargon2
      --with-tls=openssl
      --with-cyrus-sasl
      --without-systemd
      --enable-accesslog
      --enable-auditlog
      --enable-constraint
      --enable-dds
      --enable-deref
      --enable-dyngroup
      --enable-dynlist
      --enable-memberof
      --enable-ppolicy
      --enable-proxycache
      --enable-refint
      --enable-retcode
      --enable-seqmod
      --enable-sssvlv
      --enable-translucent
      --enable-unique
      --enable-valsort
    ]
    system "./configure", *args
    system "make", "depend"
    system "make"
    soelim = OS.mac? ? "mandoc_soelim" : "soelim"
    system "make", "install", "SOELIM=#{soelim}"
    system "make", "-C", "contrib/slapd-modules/passwd/sha2", "install",
           "CC=#{ENV.cc}", "prefix=#{prefix}", "moduledir=#{libexec}/openldap"
    (pkgshare/"schema").install Dir["servers/slapd/schema/*.schema"]
    (var/"run").mkpath
    (var/"openldap-data").mkpath
    # Homebrew preserves existing configuration. Supply an explicit fragment;
    # never rewrite a user's server policy in an install or upgrade hook.
    (pkgshare/"password-modules.conf").write <<~EOS
      modulepath #{opt_libexec}/openldap
      moduleload pw-sha2
      moduleload argon2
      password-hash {SSHA512}
    EOS
  end

  def caveats
    <<~EOS
      Password modules: #{opt_libexec}/openldap
      Include #{opt_pkgshare}/password-modules.conf in slapd.conf BEFORE database directives.
      This enables SSHA512 by default and optional Argon2id verification.
      Existing server configuration and password hashes are never rewritten automatically.
      CLI hashing: slappasswd -o module-path=#{opt_libexec}/openldap -o module-load=pw-sha2 -h '{SSHA512}'
      Optional Argon2id: use module-load=argon2 and -h '{ARGON2}'.
      OpenLDAP 2.6 MDB databases require export with 2.6 and import with 2.7 before use.
    EOS
  end

  service do
    run [opt_libexec/"slapd", "-d", "0", "-f", etc/"openldap/slapd.conf",
         "-h", "ldap://127.0.0.1:1389 ldaps://127.0.0.1:1636 ldapi:///"]
    keep_alive true
    working_dir var
    log_path var/"log/openldap.log"
    error_log_path var/"log/openldap.log"
  end

  test do
    sha = shell_output("#{sbin}/slappasswd -o module-path=#{libexec}/openldap -o module-load=pw-sha2 -h '{SSHA512}' -s fixture-only")
    assert_match "{SSHA512}", sha
    argon = shell_output("#{sbin}/slappasswd -o module-path=#{libexec}/openldap -o module-load=argon2 -h '{ARGON2}' -s fixture-only")
    assert_match "{ARGON2}$argon2id$", argon
    system RbConfig.ruby, tap.path/"tests/smoke.rb", prefix
  end
end
