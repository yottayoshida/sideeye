set -eu
rm -rf /s/scalafmt && mkdir -p /s/scalafmt/proj && cd /s/scalafmt/proj
printf 'version = 3.11.5\nrunner.dialect = scala3\n' > .scalafmt.conf
printf 'object A { def f(x:Int):Int={x+1}\n  val y   = f( 2 ) }\n' > a.scala
