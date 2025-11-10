when DNS_REQUEST {
    set query_name [string tolower [DNS::question name]]
    set query_type [DNS::question type]
    set qlen [string length $query_name]

    # ========== White Domains (BIND RPZ-style matching) ==========
    if { [class match -- $query_name ends_with white_Domains] } {
        set wl_key [class match -name $query_name ends_with white_Domains]
        set wl_matched 0

        # Check if key starts with "." (wildcard subdomain match)
        if { [string index $wl_key 0] eq "." } {
            # Wildcard match: .mood.com matches *.mood.com and mood.com
            set wl_matched 1
        } else {
            # Exact match only: mood.com matches only mood.com
            set keylen [string length $wl_key]
            if { $qlen == $keylen } {
                # Exact match
                set wl_matched 1
            }
            # If qlen != keylen, no match (e.g., www.mood.com does not match mood.com)
        }

        if { $wl_matched } {
            return
        }
    }

    # ========== RPZ Blacklist (Single DataGroup with BIND RPZ-style matching) ==========
    # Query single rpztw DataGroup which contains all domain => landing_ip mappings
    if { [class match -- $query_name ends_with rpztw] } {
        set rpz_key [class match -name $query_name ends_with rpztw]
        set landing_ip [class match -value $query_name ends_with rpztw]
        set rpz_matched 0

        # Check if key starts with "." (wildcard subdomain match)
        if { [string index $rpz_key 0] eq "." } {
            # Wildcard match: .evil.com matches *.evil.com and evil.com
            set rpz_matched 1
        } else {
            # Exact match only: evil.com matches only evil.com
            set keylen [string length $rpz_key]
            if { $qlen == $keylen } {
                # Exact match
                set rpz_matched 1
            }
            # If qlen != keylen, no match
        }

        if { $rpz_matched } {
            if { $query_type eq "A" } {
                DNS::answer clear
                DNS::answer insert "$query_name. 30 [DNS::question class] A $landing_ip"
                DNS::return
                return
            } else {
                DNS::answer clear
                DNS::answer insert "$query_name. 30 IN SOA ns.rpz.local. admin.rpz.local. 2023010101 3600 600 86400 30"
                DNS::return
                return
            }
        }
    }

    # ========== PhishTW Blacklist (Single DataGroup with BIND RPZ-style matching) ==========
    # Query single phishtw DataGroup
    if { [class match -- $query_name ends_with phishtw] } {
        set phish_key [class match -name $query_name ends_with phishtw]
        set landing_ip [class match -value $query_name ends_with phishtw]
        set phish_matched 0

        # Check if key starts with "." (wildcard subdomain match)
        if { [string index $phish_key 0] eq "." } {
            # Wildcard match
            set phish_matched 1
        } else {
            # Exact match only
            set keylen [string length $phish_key]
            if { $qlen == $keylen } {
                set phish_matched 1
            }
        }

        if { $phish_matched } {
            if { $query_type eq "A" } {
                DNS::answer clear
                DNS::answer insert "$query_name. 30 [DNS::question class] A $landing_ip"
                DNS::return
                return
            } else {
                DNS::answer clear
                DNS::answer insert "$query_name. 30 IN SOA ns.rpz.local. admin.rpz.local. 2023010101 3600 600 86400 30"
                DNS::return
                return
            }
        }
    }

    # ========== Local Blacklist (BIND RPZ-style matching) ==========
    if { [class match -- $query_name ends_with blacklist_Domains] } {
        set bl_key [class match -name $query_name ends_with blacklist_Domains]
        set bl_matched 0

        # Check if key starts with "." (wildcard subdomain match)
        if { [string index $bl_key 0] eq "." } {
            # Wildcard match: .mood.com matches *.mood.com and mood.com
            set bl_matched 1
        } else {
            # Exact match only: mood.com matches only mood.com
            set keylen [string length $bl_key]
            if { $qlen == $keylen } {
                # Exact match
                set bl_matched 1
            }
            # If qlen != keylen, no match
        }

        if { $bl_matched } {
            if { $query_type equals "A" } {
                DNS::answer clear
                DNS::answer insert "$query_name. 600 [DNS::question class] A 34.102.218.71"
                DNS::return
                return
            } elseif { $query_type equals "AAAA" } {
                DNS::answer clear
                DNS::answer insert "$query_name. 600 [DNS::question class] AAAA 2600:1901:0:9b4c::"
                DNS::return
                return
            }
        }
    }

    return
}
