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

    # ========== RPZ Blacklist (BIND RPZ-style matching) ==========
    set dg_ip_map {
        "phishtw_182_173_0_170" "182.173.0.170"
        "rpztw_112_121_114_76" "112.121.114.76"
        "rpztw_182_173_0_181" "182.173.0.181"
        "rpztw_210_64_24_25" "210.64.24.25"
        "rpztw_210_69_155_3" "210.69.155.3"
        "rpztw_34_102_218_71" "34.102.218.71"
        "rpztw_35_206_236_238" "35.206.236.238"
    }

    foreach {dg reply_ip} $dg_ip_map {
        if { [class match -- $query_name ends_with $dg] } {
            set rpz_key [class match -name $query_name ends_with $dg]
            set rpz_matched 0

            # Check if key starts with "." (wildcard subdomain match)
            if { [string index $rpz_key 0] eq "." } {
                # Wildcard match: .mood.com matches *.mood.com and mood.com
                set rpz_matched 1
            } else {
                # Exact match only: mood.com matches only mood.com
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
                    DNS::answer insert "$query_name. 30 [DNS::question class] A $reply_ip"
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
