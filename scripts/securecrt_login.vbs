#$language = "VBScript"
#$interface = "1.0"

crt.Screen.Synchronous = True

' This automatically generated script may need to be
' edited in order to work correctly.

Sub Main
	crt.Screen.Send "i" & chr(13)
	crt.Screen.WaitForString "Input ipaddress [ip number]: "
	crt.Screen.Send "xxx.xxx.xxx.xxx" & chr(13)
	crt.Screen.WaitForString "Input Service t[telnet]/s[ssh]/f[ftp]/sf[sftp]/rsh/c[cancel]/q[quit]: "
	crt.Screen.Send "s" & chr(13)
	crt.Screen.WaitForString "Login: "
	crt.Screen.Send "xxxxxxx" & chr(13)
	crt.Screen.WaitForString "Password: "
	crt.Screen.Send "xxxxxxxx" & chr(13)
End Sub
