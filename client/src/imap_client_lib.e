note
	description : "imaplib application root class"
	date        : "$Date$"
	revision    : "$Revision$"

class
	IMAP_CLIENT_LIB

inherit
	ARGUMENTS
	IL_CONSTANTS
	IL_IMAP_ACTION

create
	make,
	make_ssl,
	make_with_address,
	make_with_address_and_port,
	make_ssl_with_address,
	make_ssl_with_address_and_port

feature {NONE} -- Initialization

	make
		-- Create IMAP session with default address and ports
		do
			make_with_address_and_port(Default_address, Default_port)
		ensure
			network /= Void
			response_mgr /= Void
		end


	make_ssl
		-- Create SSL IMAP session with default address and ports
		do
			make_ssl_with_address_and_port(Default_address, Default_ssl_port)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_with_address (a_address: STRING)
		-- Create an IMAP session with address `a_address' and default port
		require
			address_not_void: a_address /= void
		do
			make_with_address_and_port(a_address, Default_port)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_with_address_and_port (a_address: STRING; a_port: INTEGER)
		-- Create an IMAP session `address' set to `a_address' and `port' to `a_port'
		require
			correct_port_number: a_port >= 1 and a_port <= 65535
			address_not_void: a_address /= void
		do
			create network.make_with_address_and_port(a_address, a_port)
			current_tag_number := 0
			current_tag := Tag_prefix + "0"
			last_response_received := -1
			create response_mgr.make_with_network (network)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_ssl_with_address (a_address: STRING)
		-- Create an SSL IMAP session with address `a_address' and default port
		require
			address_not_void: a_address /= void
		do
			make_ssl_with_address_and_port(a_address, Default_ssl_port)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_ssl_with_address_and_port (a_address: STRING; a_port: INTEGER)
		-- Create an SSL IMAP session `address' set to `a_address' and `port' to `a_port'
		require
			correct_port_number: a_port >= 1 and a_port <= 65535
			address_not_void: a_address /= void
		do
			network := create {IL_SSL_NETWORK}.make_with_address_and_port(a_address, a_port)
			current_tag_number := 0
			current_tag := Tag_prefix + "0"
			last_response_received := -1
			create response_mgr.make_with_network (network)
		ensure
			network /= Void
			response_mgr /= Void
		end

feature -- Basic Commands

	logout
			-- Attempt to logout
		do
			network.send_command (get_tag, get_command (Logout_action), create {ARRAYED_LIST[STRING]}.make (0))
		end

	get_capability: LINKED_LIST[STRING]
		require
			network.is_connected
		local
			parser: IL_PARSER
			response: IL_SERVER_RESPONSE
			tag: STRING
		do
			tag := get_tag
			network.send_command (tag, get_command(Capability_action), create {ARRAYED_LIST[STRING]}.make (0))
			response := get_response (tag)

			check correct_response_received: response.untagged_response_count = 1 or response.is_error end

			if not response.is_error then
				create parser.make_from_text(response.get_untagged_response(0))
				Result := parser.match_capabilities
			else
				create Result.make
			end


		end

feature -- Not connected commands

	connect
		-- Attempt to create a connection to the IMAP server
		do
			network.connect
			check
				response_mgr.was_connection_ok
			end
			network.set_state ({IL_NETWORK_STATE}.not_authenticated_state)
		ensure
			network.is_connected
		end

feature -- Not authenticated commands

	login ( a_user_name: STRING; a_password: STRING)
			-- Attempt to login
		require
			supports_action: supports_action(Login_action)
		local
			args:LINKED_LIST[STRING]
		do
			create args.make
			args.extend (a_user_name)
			args.extend (a_password)
			network.send_command (get_tag, get_command (Login_action), args)
			network.update_imap_state(response_mgr.read_response (current_tag), {IL_NETWORK_STATE}.authenticated_state)
		end


feature -- Authenticated commands

	list ( a_reference_name: STRING; a_name: STRING )
			-- List the mailbox at `a_reference_name' with name `a_name'
			-- `a_name' may use wildcards
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args:LINKED_LIST[STRING]
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			network.send_command (get_tag, get_command (List_action), args)
		end

	get_list ( a_reference_name: STRING; a_name: STRING ): LINKED_LIST[IL_MAILBOX]
			-- Returns a list of the mailbox at `a_reference_name' with name `a_name'
			-- `a_name' may use wildcards
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args:LINKED_LIST[STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_MAILBOX_LIST_PARSER
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			tag := get_tag
			network.send_command (tag, get_command (List_action), args)

			response := get_response (tag)
			create parser.make_from_response (response)
			if parser.get_status ~ Command_ok_label then
				Result := parser.get_list
			else
				create Result.make
			end

		end


	select_mailbox ( a_mail_box_name: STRING )
		require
			supports_action(Select_action)
		local
			tag: STRING
			arguments: ARRAYED_LIST[STRING]
		do
			tag := get_tag
			create arguments.make (1)
			arguments.put_i_th (a_mail_box_name, 0)
			network.send_command (tag, get_command (Select_action), arguments)
		end


feature -- Basic Operations

	is_connected:BOOLEAN
			-- Returns true iff the network is connected to the socket
		do
			if current_tag_number > 0 then
				response_mgr.update_responses (current_tag)
			end
			Result := network.is_connected
		end

	-- TODO: See if this is really needed
	supports_action(action: NATURAL): BOOLEAN
		-- Returns true if the command `action' is supported in current context
	local
		capability_list: LINKED_LIST[STRING]
	do
		--capability_list := get_capability

		--Result := false
		--across
		--	capability_list as cap
		--loop
		--	if cap.item ~ get_command(action) then
				Result := true
		--	end
		--end
	end

	get_last_response: IL_SERVER_RESPONSE
			-- Returns the response for the last command sent
	do
		Result := get_response (current_tag)
	ensure
		Result /= Void
	end

feature -- Access

	network: IL_NETWORK

feature {NONE} -- Implementation

	current_tag_number: INTEGER

	current_tag: STRING

	last_response_received: INTEGER

	get_tag: STRING
		-- increments the `current_tag_number' and returns a new tag, greater tha the last one
		do
			current_tag_number := current_tag_number + 1
			create Result.make_empty
			Result.copy (Tag_prefix)
			Result.append_integer (current_tag_number)
			current_tag := Result
		ensure
			current_tag_number_increased: current_tag_number > old current_tag_number
		end

	get_response (tag: STRING): IL_SERVER_RESPONSE
			-- Returns the server response that the server gave for command with tag `tag'
		require
			tag_not_empty: tag /= Void and then not tag.is_empty

		local
			parser: IL_PARSER
			tag_number: INTEGER
		do
			create parser.make_from_text (tag)
			tag_number := parser.get_number
			check
				correct_tag: tag_number > last_response_received and tag_number <= current_tag_number
			end
			Result := response_mgr.get_response (tag)

			last_response_received := tag_number
		ensure
			Result /= Void
		end

 	response_mgr: IL_RESPONSE_MANAGER


end
