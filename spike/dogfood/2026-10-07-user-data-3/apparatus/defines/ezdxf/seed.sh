set -eu
rm -rf /s/dxf /s/dxf-in && mkdir -p /s/dxf /s/dxf-in
/opt/py/bin/python -I -c "import ezdxf; doc=ezdxf.new('R2018'); msp=doc.modelspace(); [msp.add_line((i,0),(i,10)) for i in range(20)]; doc.saveas('/s/dxf/drawing.dxf')"
/opt/py/bin/python -I -c "p='/s/dxf/drawing.dxf'; t=open(p).read(); open(p,'w').write('999\ndrawn by hand, revision 7\n'+t)"
test "$(grep -c '^999' /s/dxf/drawing.dxf)" = 1
