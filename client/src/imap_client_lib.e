note
	description: "An library to connect to a server via the Internet Message Access Protocol"
	author: "Basile Maret"
	EIS: "name=IMAP4rev1", "src=https://tools.ietf.org/html/rfc3501", "protocol=URI"

class
	IMAP_CLIENT_LIB

inherit

	IL_CONSTANTS

	IL_IMAP_ACTION

create
	make, make_ssl, make_with_address, make_with_address_and_port, make_ssl_with_address, make_ssl_with_address_and_port

feature {NONE} -- Initialization

	make
			-- Create IMAP session with default address and ports
		do
			make_with_address_and_port (Default_address, Default_port)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_ssl
			-- Create SSL IMAP session with default address and ports
		do
			make_ssl_with_address_and_port (Default_address, Default_ssl_port)
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_with_address (a_address: STRING)
			-- Create an IMAP session with address `a_address' and default port
		require
			address_not_void: a_address /= void
		do
			make_with_address_and_port (a_address, Default_port)
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
			create network.make_with_address_and_port (a_address, a_port)
			current_tag_number := 0
			current_tag := Tag_prefix + "0"
			create response_mgr.make_with_network (network)
			current_mailbox.unselect
		ensure
			network /= Void
			response_mgr /= Void
		end

	make_ssl_with_address (a_address: STRING)
			-- Create an SSL IMAP session with address `a_address' and default port
		require
			address_not_void: a_address /= void
		do
			make_ssl_with_address_and_port (a_address, Default_ssl_port)
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
			network := create {IL_SSL_NETWORK}.make_with_address_and_port (a_address, a_port)
			current_tag_number := 0
			current_tag := Tag_prefix + "0"
			create response_mgr.make_with_network (network)
			current_mailbox.unselect
		ensure
			network /= Void
			response_mgr /= Void
		end

feature -- Basic Commands

	logout
			-- Attempt to logout
		note
			EIS: "name=LOGOUT", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.1.3"
		do
			send_action (Logout_action, create {ARRAYED_LIST [STRING]}.make (0))
			network.set_state ({IL_NETWORK_STATE}.not_connected_state)
		end

	get_capability: LIST [STRING]
		note
			EIS: "name=CAPABILITY", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.1.1"
		require
			network.is_connected
		local
			parser: IL_PARSER
			response: IL_SERVER_RESPONSE
			tag: STRING
		do
			tag := get_tag
			send_action_with_tag (tag, Capability_action, create {ARRAYED_LIST [STRING]}.make (0))
			response := get_response (tag)
			check
				correct_response_received: response.untagged_response_count = 1 or response.is_error
			end
			if not response.is_error then
				create parser.make_from_text (response.untagged_response (0))
				Result := parser.match_capabilities
			else
				create {ARRAYED_LIST [STRING]}Result.make (0)
			end
		end

	noop
			-- Send a Noop command
		note
			EIS: "name=NOOP", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.1.2"
		do
			send_action (Noop_action, create {ARRAYED_LIST [STRING]}.make (0))
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

	starttls
			-- Start tls negociation
		note
			EIS: "name=STARTTLS", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.2.1"
		do
			send_action (Starttls_action, create {ARRAYED_LIST [STRING]}.make (0))
		end

	login (a_user_name: STRING; a_password: STRING)
			-- Attempt to login
		note
			EIS: "name=LOGIN", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.2.3"
		require
			a_user_name_not_empty: a_user_name /= Void and then not a_user_name.is_empty
			a_password_not_empty: a_password /= Void and then not a_password.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_user_name)
			args.extend (a_password)
			send_action (Login_action, args)
			network.update_imap_state (response_mgr.response (current_tag), {IL_NETWORK_STATE}.authenticated_state)
		end

feature -- Authenticated commands

	select_mailbox (a_mailbox_name: STRING)
			-- Select the mailbox `a_mailbox_name' and save it into `current_mailbox'
		note
			EIS: "name=SELECT", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.1"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
			response: IL_SERVER_RESPONSE
			tag: STRING
			parser: IL_MAILBOX_PARSER
		do
			current_mailbox.unselect
			tag := get_tag
			create args.make
			args.extend (a_mailbox_name)
			send_action_with_tag (tag, Select_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				create parser.make_from_response (response, a_mailbox_name)
				parser.parse_mailbox
				network.update_imap_state (response, {IL_NETWORK_STATE}.selected_state)
			end
		end

	examine_mailbox (a_mailbox_name: STRING)
			-- Select the mailbox `a_mailbox_name' in read only and save it into `current_mailbox'
		note
			EIS: "name=EXAMINE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.2"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
			response: IL_SERVER_RESPONSE
			tag: STRING
			parser: IL_MAILBOX_PARSER
		do
			current_mailbox.unselect
			tag := get_tag
			create args.make
			args.extend (a_mailbox_name)
			send_action_with_tag (tag, Examine_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				create parser.make_from_response (response, a_mailbox_name)
				parser.parse_mailbox
				network.update_imap_state (response, {IL_NETWORK_STATE}.selected_state)
			end
		end

	create_mailbox (a_mailbox_name: STRING)
			-- Create the mailbox `a_mailbox_name'
		note
			EIS: "name=CREATE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.3"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_mailbox_name)
			send_action (Create_action, args)
		end

	delete_mailbox (a_mailbox_name: STRING)
			-- Delete the mailbox `a_mailbox_name'
		note
			EIS: "name=DELETE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.4"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_mailbox_name)
			send_action (Delete_action, args)
		end

	rename_mailbox (a_mailbox_name: STRING; a_new_name: STRING)
			-- Rename the mailbox `a_mailbox_name' to `a_new_name'
		note
			EIS: "name=RENAME", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.5"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
			a_new_name_not_empty: a_new_name /= Void and then not a_new_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_mailbox_name)
			args.extend (a_new_name)
			send_action (Rename_action, args)
		end

	subscribe (a_mailbox_name: STRING)
			-- Subscribe to the mailbox `a_mailbox_name'
		note
			EIS: "name=SUBSCRIBE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.6"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_mailbox_name)
			send_action (Subscribe_action, args)
		end

	unsubscribe (a_mailbox_name: STRING)
			-- Unsubscribe from the mailbox `a_mailbox_name'
		note
			EIS: "name=UNSUBSCRIBE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.7"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_mailbox_name)
			send_action (Unsubscribe_action, args)
		end

	list (a_reference_name: STRING; a_name: STRING)
			-- List the names at `a_reference_name' in mailbox `a_name'
			-- `a_name' may use wildcards
		note
			EIS: "name=LIST", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.8"
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			send_action (List_action, args)
		end

	get_list (a_reference_name: STRING; a_name: STRING): LIST [IL_NAME]
			-- Returns a list of the names at `a_reference_name' in mailbox `a_name'
			-- `a_name' may use wildcards
		note
			EIS: "name=LIST", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.8"
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_NAME_LIST_PARSER
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			tag := get_tag
			send_action_with_tag (tag, List_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				create parser.make_from_response (response, false)
				Result := parser.mailbox_names
			else
				create {ARRAYED_LIST [IL_NAME]}Result.make (0)
			end
		end

	lsub (a_reference_name: STRING; a_name: STRING)
			-- Send command lsub for `a_reference_name' in mailbox `a_name'
			-- `a_name' may use wildcards
		note
			EIS: "name=LSUB", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.9"
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			send_action (Lsub_action, args)
		end

	get_lsub (a_reference_name: STRING; a_name: STRING): LIST [IL_NAME]
			-- Returns a list of the name for the command lsub at `a_reference_name' in mailbox `a_name'
			-- `a_name' may use wildcards
		note
			EIS: "name=LSUB", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.9"
		require
			args_not_void: a_reference_name /= Void and a_name /= Void
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_NAME_LIST_PARSER
		do
			create args.make
			args.extend ("%"" + a_reference_name + "%"")
			args.extend ("%"" + a_name + "%"")
			tag := get_tag
			send_action_with_tag (tag, Lsub_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				create parser.make_from_response (response, true)
				Result := parser.mailbox_names
			else
				create {ARRAYED_LIST [IL_NAME]}Result.make (0)
			end
		end

	get_status (a_mailbox_name: STRING; status_data: LIST [STRING]): STRING_TABLE [INTEGER]
			-- Return the status of the mailbox `a_mailbox_name' for status data in list `status_data'
		note
			EIS: "name=STATUS", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.10"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
			status_data_not_empty: status_data /= Void and then not status_data.is_empty
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_PARSER
		do
			create args.make
			args.extend (a_mailbox_name)
			args.extend (string_from_list (status_data))
			tag := get_tag
			send_action_with_tag (tag, Status_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label and then response.untagged_response_count > 0 then
				create parser.make_from_text (response.untagged_responses.at (1))
				Result := parser.status_data
			else
				create Result.make (0)
			end
		end

	append (a_mailbox_name: STRING; flags: LIST [STRING]; date_time: STRING; message_literal: STRING)
			-- Append `message_literal' as a new message to the end of the mailbox `a_mailbox_name'
			-- The flags in the list `flags' are set to the resulting message and if `data_time' is not empty, it is set as internal date to the message.
		note
			EIS: "name=APPEND", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.3.11"
		require
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
			flags_not_void: flags /= Void
			date_time_not_void: date_time /= Void
			message_literal_not_empty: message_literal /= Void and then not message_literal.is_empty
		local
			args: LINKED_LIST [STRING]
			flags_string: STRING
		do
			create args.make
			args.extend (a_mailbox_name)
			flags_string := string_from_list (flags)
			if not flags_string.is_empty then
				args.extend (flags_string)
			end
			if not date_time.is_empty then
				args.extend (date_time)
			end
			args.extend ("{" + message_literal.count.out + "}")
			send_action (Append_action, args)
			if needs_continuation then
				send_command_continuation (message_literal)
			end
		end

feature -- Selected commands

	check_command
			-- Request a checkpoint
		note
			EIS: "name=CHECK", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.1"
		do
			send_action (Check_action, create {ARRAYED_LIST [STRING]}.make (0))
		end

	close
			-- Close the selected mailbox. Switch to authenticated state on success
		note
			EIS: "name=CLOSE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.2"
		do
			send_action (Close_action, create {ARRAYED_LIST [STRING]}.make (0))
			network.update_imap_state (response_mgr.response (current_tag), {IL_NETWORK_STATE}.authenticated_state)
		end

	expunge
			-- Send expunge command.
		note
			EIS: "name=EXPUNGE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.3"
		do
			send_action (Expunge_action, create {ARRAYED_LIST [STRING]}.make (0))
		end

	get_expunge: LIST [INTEGER]
			-- Send expunge command. Returns a list of the deleted messages
		note
			EIS: "name=EXPUNGE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.3"
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_EXPUNGE_PARSER
		do
			create args.make
			tag := get_tag
			send_action_with_tag (tag, Expunge_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				create parser.make_from_response (response)
				Result := parser.parse_expunged
			else
				create {ARRAYED_LIST [INTEGER]}Result.make (0)
			end
		end

	search (charset: STRING; criterias: LIST [STRING]): LIST [INTEGER]
			-- Return a list of message that match the criterias `criterias'
		note
			EIS: "name=SEARCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.4"
		require
			criterias_not_void: criterias /= Void
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
			parser: IL_PARSER
		do
			tag := get_tag
			create args.make
			if charset /= Void and then not charset.is_empty then
				args.extend ("CHARSET " + charset)
			end
			across
				criterias as criteria
			loop
				args.extend (criteria.item)
			end
			send_action_with_tag (tag, Search_action, args)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label and then response.untagged_response_count = 1 then
				create parser.make_from_text (response.untagged_responses.at (1))
				Result := parser.search_results
			else
				create {ARRAYED_LIST [INTEGER]}Result.make (0)
			end
		end

	fetch (a_sequence_set: IL_SEQUENCE_SET; data_items: LIST [STRING]): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for data items `data_items'
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_not_empty: data_items /= Void and then not data_items.is_empty
		do
			Result := fetch_string (a_sequence_set, string_from_list (data_items))
		end

	fetch_all (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for macro ALL
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string (a_sequence_set, All_macro)
		end

	fetch_fast (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for macro FAST
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string (a_sequence_set, Fast_macro)
		end

	fetch_full (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for macro FULL
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string (a_sequence_set, Full_macro)
		end

	fetch_string (a_sequence_set: IL_SEQUENCE_SET; data_items: STRING): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for data items `data_items'
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_not_empty: data_items /= Void and then not data_items.is_empty
		do
			Result := fetch_implementation (a_sequence_set, data_items, false)
		end

	fetch_messages (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_MESSAGE, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' and return the data as a hash table maping the uid of the message to the message
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_message_implementation (a_sequence_set, false)
		end

	fetch_uid (a_sequence_set: IL_SEQUENCE_SET; data_items: LIST [STRING]): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' for data items `data_items'
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_not_empty: data_items /= Void and then not data_items.is_empty
		do
			Result := fetch_string_uid (a_sequence_set, string_from_list (data_items))
		end

	fetch_all_uid (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' for macro ALL
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string_uid (a_sequence_set, All_macro)
		end

	fetch_fast_uid (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' for macro FAST
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string_uid (a_sequence_set, Fast_macro)
		end

	fetch_full_uid (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' for macro FULL
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_string_uid (a_sequence_set, Full_macro)
		end

	fetch_string_uid (a_sequence_set: IL_SEQUENCE_SET; data_items: STRING): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' for data items `data_items'
			-- Returns a hash table maping the sequence number of the message to an il_fetch data structure
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_not_empty: data_items /= Void and then not data_items.is_empty
		do
			Result := fetch_implementation (a_sequence_set, data_items, true)
		end

	fetch_messages_uid (a_sequence_set: IL_SEQUENCE_SET): HASH_TABLE [IL_MESSAGE, NATURAL]
			-- Send a fetch command with sequence set of uids `a_sequence_set' and return the data as a hash table maping the uid of the message to the message
		note
			EIS: "name=FETCH", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.5"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		do
			Result := fetch_message_implementation (a_sequence_set, true)
		end

	copy_messages (a_sequence_set: IL_SEQUENCE_SET; a_mailbox_name: STRING)
			-- Copy the messages in `a_sequence_set' to mailbox `a_mailbox_name'
		note
			EIS: "name=COPY", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.7"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_sequence_set.string)
			args.extend (a_mailbox_name)
			send_action (Copy_action, args)
		end

	copy_messages_uid (a_sequence_set: IL_SEQUENCE_SET; a_mailbox_name: STRING)
			-- Copy the messages with uids in `a_sequence_set' to mailbox `a_mailbox_name'
		note
			EIS: "name=COPY", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.7"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			a_mailbox_name_not_empty: a_mailbox_name /= Void and then not a_mailbox_name.is_empty
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_sequence_set.string)
			args.extend (a_mailbox_name)
			send_action (Uid_copy_action, args)
		end

	store (a_sequence_set: IL_SEQUENCE_SET; data_item_name: STRING; data_item_values: LIST [STRING])
			-- Alter data for messages in `a_sequence_set'. Change the messages according to `data_item_name' with arguments `data_item_values'
		note
			EIS: "name=STORE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.6"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_name_not_empty: data_item_name /= Void and then not data_item_name.is_empty
			data_item_value_not_void: data_item_values /= Void
		do
			store_implementation (get_tag, a_sequence_set, data_item_name, data_item_values, false)
		end

	get_store (a_sequence_set: IL_SEQUENCE_SET; data_item_name: STRING; data_item_values: LIST [STRING]): HASH_TABLE [IL_FETCH, NATURAL]
			-- Alter data for messages in `a_sequence_set'. Change the messages according to `data_item_name' with arguments `data_item_values'
			-- Returns a hash table maping the uid of the message to an il_fetch data structure for every FETCH response received
		note
			EIS: "name=STORE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.6"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_name_not_empty: data_item_name /= Void and then not data_item_name.is_empty
			data_item_value_not_void: data_item_values /= Void
		local
			tag: STRING
			response: IL_SERVER_RESPONSE
		do
			tag := get_tag
			store_implementation (tag, a_sequence_set, data_item_name, data_item_values, false)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				Result := response.fetch_responses
			else
				create Result.make (0)
			end
		end

	store_uid (a_sequence_set: IL_SEQUENCE_SET; data_item_name: STRING; data_item_values: LIST [STRING])
			-- Alter data for messages with uid in `a_sequence_set'. Change the messages according to `data_item_name' with arguments `data_item_values'
		note
			EIS: "name=STORE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.6"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_name_not_empty: data_item_name /= Void and then not data_item_name.is_empty
			data_item_value_not_void: data_item_values /= Void
		do
			store_implementation (get_tag, a_sequence_set, data_item_name, data_item_values, true)
		end

	get_store_uid (a_sequence_set: IL_SEQUENCE_SET; data_item_name: STRING; data_item_values: LIST [STRING]): HASH_TABLE [IL_FETCH, NATURAL]
			-- Alter data for messages with uid in `a_sequence_set'. Change the messages according to `data_item_name' with arguments `data_item_values'
			-- Returns a hash table maping the uid of the message to an il_fetch data structure for every FETCH response received
		note
			EIS: "name=STORE", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.6"
			EIS: "name=UID", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.4.8"
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_name_not_empty: data_item_name /= Void and then not data_item_name.is_empty
			data_item_value_not_void: data_item_values /= Void
		local
			tag: STRING
			response: IL_SERVER_RESPONSE
		do
			tag := get_tag
			store_implementation (tag, a_sequence_set, data_item_name, data_item_values, true)
			response := get_response (tag)
			if not response.is_error and then response.status ~ Command_ok_label then
				Result := response.fetch_responses
			else
				create Result.make (0)
			end
		end

	check_for_changes: BOOLEAN
			-- Sends a noop command and returns true iff the server sends back any change to the current mailbox
		note
			EIS: "name=NOOP", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-6.1.2"
			EIS: "name=Message Status Update", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-5.2"
		do
			noop
			receive
			Result := current_mailbox.was_updated
		end

feature -- Basic Operations

	send_action (a_action: NATURAL; arguments: LIST [STRING])
			-- Send the command for `a_action' with argument list `arguments'
		require
			action_supported: supports_action (a_action)
			arguments_not_void: arguments /= Void
			network.is_connected
		do
			send_command (get_command (a_action), arguments)
		end

	send_action_with_tag (a_tag: STRING; a_action: NATURAL; arguments: LIST [STRING])
			-- Send the command for `a_action' with argument list `arguments' and with tag `a_tag'
		require
			tag_not_empty: a_tag /= Void and then not a_tag.is_empty
			action_supported: supports_action (a_action)
			arguments_not_void: arguments /= Void
			network.is_connected
		do
			network.send_command (a_tag, get_command (a_action), arguments)
		end

	send_command (a_command: STRING; arguments: LIST [STRING])
			-- Send the command `a_command' with argument list `arguments'
		require
			a_command_not_empty: a_command /= Void and then not a_command.is_empty
			arguments_not_void: arguments /= Void
			network.is_connected
		do
			network.send_command (get_tag, a_command, arguments)
		end

	send_command_continuation (a_continuation: STRING)
			-- Send the command continuation `a_continuation'
		require
			a_continuation_not_empty: a_continuation /= Void and then not a_continuation.is_empty
			needs_continuation: needs_continuation
			network.is_connected
		do
			network.send_command_continuation (a_continuation)
		end

	get_last_response: IL_SERVER_RESPONSE
			-- Returns the response for the last command sent
		do
			Result := get_response (current_tag)
		ensure
			Result /= Void
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
			tag_number := parser.number
			check
				correct_tag: tag_number > 0 and tag_number <= current_tag_number
			end
			Result := response_mgr.response (tag)
		ensure
			Result /= Void
		end

	receive
			-- Read socket for responses
		do
			if current_tag_number > 0 then
				response_mgr.update_responses (current_tag)
			end
		end

	get_last_tag: STRING
			-- Returns the tag of the last command sent
		do
			Result := current_tag
		end

	is_connected: BOOLEAN
			-- Returns true iff the network is connected to the socket
		do
			receive
			Result := network.is_connected
		end

	get_current_state: NATURAL
			-- Returns the current IMAP state
		note
			EIS: "name=States", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-3"
		do
			Result := network.state
		end

	supports_action (action: NATURAL): BOOLEAN
			-- Returns true if the command `action' is supported in current context
		do
			Result := network.check_action (network.state, action)
		end

	needs_continuation: BOOLEAN
			-- Return true iff the last response from the server was a command continuation request
		note
			EIS: "name=Command Continuation Request", "protocol=URI", "src=https://tools.ietf.org/html/rfc3501#section-7.5"
		do
			receive
			Result := network.needs_continuation
		end

feature -- Access

	network: IL_NETWORK

feature {NONE} -- Implementation

	current_tag_number: INTEGER
			-- The number of the tag of the last message sent

	current_tag: STRING
			-- The tag of the last message sent

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

	fetch_implementation (a_sequence_set: IL_SEQUENCE_SET; data_items: STRING; is_uid: BOOLEAN): HASH_TABLE [IL_FETCH, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set' for data items `data_items'
			-- The sequence set will represent uids iff `is_uid' is set to true
			-- Returns a hash table maping the uid of the message to an il_fetch data structure
		require
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_not_empty: data_items /= Void and then not data_items.is_empty
		local
			args: LINKED_LIST [STRING]
			tag: STRING
			response: IL_SERVER_RESPONSE
		do
			create args.make
			args.extend (a_sequence_set.string)
			args.extend (data_items)
			tag := get_tag
			if is_uid then
				send_action_with_tag (tag, Uid_fetch_action, args)
			else
				send_action_with_tag (tag, Fetch_action, args)
			end

			response := get_response (tag)
			if response.status ~ Command_ok_label then
				Result := response.fetch_responses
			else
				create Result.make (0)
			end
		end

	fetch_message_implementation (a_sequence_set: IL_SEQUENCE_SET; is_uid: BOOLEAN): HASH_TABLE [IL_MESSAGE, NATURAL]
			-- Send a fetch command with sequence set `a_sequence_set'
			-- The sequence set will represent uids iff `is_uid' is set to true
			-- Returns the data as a hash table maping the uid of the message to the message
		require
			a_sequence_set_not_void: a_sequence_set /= Void
		local
			fetch_return: HASH_TABLE [IL_FETCH, NATURAL]
			data_items: LINKED_LIST [STRING]
		do
			create data_items.make
			data_items.extend (body_data_item)
			data_items.extend (envelope_data_item)
			data_items.extend (flags_data_item)
			data_items.extend (internaldate_data_item) -- TODO: Not parsed yet
			data_items.extend (header_data_item)
			data_items.extend (size_data_item)
			data_items.extend (text_data_item)
			data_items.extend (uid_data_item)
			fetch_return := fetch_implementation (a_sequence_set, string_from_list (data_items), is_uid)

			create Result.make (fetch_return.count)
			across
				fetch_return as f
			loop
				Result.put (create {IL_MESSAGE}.make_from_fetch (f.item), f.key)
			end

		end

	store_implementation (a_tag: STRING; a_sequence_set: IL_SEQUENCE_SET; data_item_name: STRING; data_item_values: LIST [STRING]; is_uid: BOOLEAN)
			-- send STORE command for arguments `a_sequence_set'. Change the messages according to `data_item_name' with arguments `data_item_values'
			-- `a_sequence_set' represents uid iff `is_uid' is set to true
		require
			a_tag_not_empty: a_tag /= Void and then not a_tag.is_empty
			a_sequence_set_not_void: a_sequence_set /= Void
			data_item_name_not_empty: data_item_name /= Void and then not data_item_name.is_empty
			data_item_value_not_void: data_item_values /= Void
		local
			args: LINKED_LIST [STRING]
		do
			create args.make
			args.extend (a_sequence_set.string)
			args.extend (data_item_name)
			args.extend (string_from_list (data_item_values))
			if is_uid then
				send_action_with_tag (a_tag, Uid_store_action, args)
			else
				send_action_with_tag (a_tag, Store_action, args)
			end
		end

	response_mgr: IL_RESPONSE_MANAGER

	string_from_list (a_list: LIST [STRING]): STRING
			-- Returns a string begining with "(" and ending with ")" and containing all the elements of `a_list' separated by " "
			-- Returns an empty string iff a_list is empty
		require
			a_list_not_void: a_list /= Void
		do
			create Result.make_empty
			across
				a_list as elem
			loop
				Result.append (elem.item + " ")
			end
			if not Result.is_empty then
				Result.remove_tail (1)
				Result := "(" + Result + ")"
			end
		ensure
			empty_list_iff_empty_result: a_list.is_empty = Result.is_empty
		end

invariant
	mailbox_selected_in_selected_state: (network.state = network.Selected_state) = current_mailbox.is_selected

note
	copyright: "2015-2016, Maret Basile, Eiffel Software"
	license: "Eiffel Forum License v2 (see http://www.eiffel.com/licensing/forum.txt)"
end
