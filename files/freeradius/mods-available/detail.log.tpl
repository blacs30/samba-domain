# -*- text -*-
#
#  $Id: b91cf7cb24744ee96e390aa4d7bd5f3ad4c0c0ee $
####################################################################
#
#  More examples of doing detail logs.

#
#  Many people want to log authentication requests.
#  Rather than modifying the server core to print out more
#  messages, we can use a different instance of the 'detail'
#  module, to log the authentication requests to a file.
#
#  You will also need to un-comment the 'auth_log' line
#  in the 'authorize' section, below.
#
detail auth_log {
    filename = ${radacctdir}/%{%{Packet-Src-IP-Address}:-%{Packet-Src-IPv6-Address}}/auth-detail-%Y%m%d

    #
    #  This MUST be 0600, otherwise anyone can read
    #  the users passwords!
    permissions = 0600

    # You may also strip out passwords completely
    suppress {
        User-Password
    }
}

#
#  This module logs authentication reply packets sent
#  to a NAS.  Both Access-Accept and Access-Reject packets
#  are logged.
#
#  You will also need to un-comment the 'reply_log' line
#  in the 'post-auth' section, below.
#
detail reply_log {

    # CHANGED by SALT
    # filename = ${radacctdir}/%{%{Packet-Src-IP-Address}:-%{Packet-Src-IPv6-Address}}/reply-detail-%Y%m%d
    filename = ${radacctdir}/reply-detail

    permissions = 0600
}

#
#  This module logs packets proxied to a home server.
#
#  You will also need to un-comment the 'pre_proxy_log' line
#  in the 'pre-proxy' section, below.
#
detail pre_proxy_log {
    filename = ${radacctdir}/%{%{Packet-Src-IP-Address}:-%{Packet-Src-IPv6-Address}}/pre-proxy-detail-%Y%m%d

    #
    #  This MUST be 0600, otherwise anyone can read
    #  the users passwords!
    permissions = 0600

    # You may also strip out passwords completely
    #suppress {
        # User-Password
    #}
}

#
#  This module logs response packets from a home server.
#
#  You will also need to un-comment the 'post_proxy_log' line
#  in the 'post-proxy' section, below.
#
detail post_proxy_log {
    filename = ${radacctdir}/%{%{Packet-Src-IP-Address}:-%{Packet-Src-IPv6-Address}}/post-proxy-detail-%Y%m%d

    permissions = 0600
}

