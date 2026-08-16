#!/bin/sh
exec lbdb-fetchaddr -f "$TOY_STATE/m_inmail" < "$TOY_STATE/mail.eml"
