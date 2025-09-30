when DNS_REQUEST {
    # 取得查詢資訊
    set fqdn_name [string tolower [DNS::question name]]
    set sip [IP::client_addr]
    set type [DNS::question type]
    set found 0
    set reply_name ""

    # 在 rpz DataGroup 中查找 FQDN
    set found [class match -- $fqdn_name ends_with rpz]
    if { $found } {
        # 找出 DataGroup key 和 reply IP
        set key [class match -name $fqdn_name ends_with rpz]
        set reply_name [class match -value $fqdn_name ends_with rpz]

        # 邊界檢查：確保完全匹配或前綴為「.」
        # 避免 evilexample.com 匹配到 example.com
        set keylen [string length $key]
        set fqdnlen [string length $fqdn_name]
        if { $fqdnlen > $keylen } {
            set prefix [string index $fqdn_name [expr {$fqdnlen - $keylen - 1}]]
            if { $prefix ne "." } {
                set found 0
            }
        }
    }

    # 日誌記錄 (可選，除錯時開啟)
    # log local0. "fqdn_name: $fqdn_name, found: $found, type: $type, reply: $reply_name, from: $sip"

    # 根據查詢類型回應
    if { $found && $type eq "A" } {
        # A 記錄查詢：直接返回 Landing IP
        DNS::answer insert "[DNS::question name]. 600 [DNS::question class] [DNS::question type] $reply_name"
        DNS::return
    } elseif { $found } {
        # 其他類型查詢：返回 SOA 記錄
        DNS::authority insert "rpztw. 600 IN SOA localhost. This.is.an.infringing.website.rpztw. 1653872401 300 60 86400 60"
        DNS::return
    }
}