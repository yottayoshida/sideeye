set -eu
rm -rf /s/hexapdf && mkdir -p /s/hexapdf && cd /s/hexapdf
ruby -e 'require "hexapdf"; d=HexaPDF::Document.new; 3.times{|i| d.pages.add.canvas.font("Helvetica",size:12).text("page #{i}",at:[50,700])}; d.write("a.pdf")'
