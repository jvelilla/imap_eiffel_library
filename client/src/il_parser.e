note

	description: "Summary description for {IL_PARSER}."
	author: ""
	date: "$Date$"
	revision: "$Revision$"

class
	IL_PARSER

inherit
	IL_CONSTANTS
	IL_IMAP_ACTION

create
	make_from_text

feature {NONE} -- Initialization

	make_from_text (a_text: STRING)
			-- Create a parser which will parse `a_text'
		require
			a_text_not_empty: not a_text.is_empty
		do
			text := a_text
			create regex.make
		ensure
			text_set: text = a_text
		end

feature -- Access

	text: STRING
		-- The string we need to parse

	regex: RX_PCRE_REGULAR_EXPRESSION


feature -- Basic operations

	matches_connection_ok: BOOLEAN
			-- Returns true iff the text matches a successful imap connection response
		do
			regex.compile (Connection_ok_pattern)
			Result := regex.matches (text)
		end

	match_capabilities: LINKED_LIST[STRING]
			-- Returns a list of all the capabilities matched in text
			-- Returns an empty list if `text' doesn't match a correct capability response
		do
			regex.compile (Capabilities_pattern)

			create Result.make

			if regex.matches (text) then
				create regex.make
				regex.compile (Capability_pattern)
				from
					regex.match (text)
				until
					not regex.has_matched
				loop
					add_capability_from_text(Result, regex.captured_substring (0))
					regex.next_match
				end

				Result.extend (get_command (Noop_action))
				Result.extend (get_command (Capability_action))
				Result.extend (get_command (Logout_action))
			end
		end

	get_text: STRING
		-- Returns the text
		do
			Result := text
		end

	get_tag: STRING
		-- Returns the tag from the text
		do
			regex.compile (Tag_pattern)
			if regex.matches (text) then
				Result := regex.captured_substring (0)
			else
				Result := ""
			end
		ensure
			not_empty: not Result.is_empty
		end

	get_status: STRING
			-- Returns the status from the text
		do
			regex.compile (Status_pattern)
			if regex.matches (text) then
				Result := regex.captured_substring (1)
			else
				Result := ""
			end
		ensure
			correct_status: Result.is_equal(Command_ok_label) or Result.is_equal(Command_bad_label) or Result.is_equal(Command_no_label)
		end

	get_number: INTEGER
			-- Returns the integer after "il" in `text'
		do
			regex.compile (Integer_from_tag_pattern)
			if regex.matches (text) then
				Result := regex.captured_substring (1).to_integer
			else
				Result := -1
			end
		end

feature -- Constants

	Connection_ok_pattern: STRING = "^\* OK (.*)$"

	Capability_pattern: STRING = "(([A-Z]|=|rev|\d|\+|-)+)"

	Capabilities_pattern: STRING = "^\* ([A-Z]|=|rev|\d|\+|-| )*IMAP4rev1([A-Z]|=|rev|\d|\+|-| )*%R$"

	Untagged_response_pattern: STRING = "^\* (.*)$"

	Tag_pattern: STRING = "^(\*|il\d+)"

	Integer_from_tag_pattern: STRING = "^il(\d+)$"

	Status_pattern: STRING = "^il\d+ (OK|NO|BAD)"

feature {NONE} -- Constants

	Tag_position: INTEGER = 1

	Command_result_position: INTEGER = 2

	Untagged_label: String = "*"


feature {NONE} -- Implementation

	add_capability_from_text( a_list: LINKED_LIST[STRING]; a_text: STRING)
			-- Parses the text and will add a new command to `a_list' if it can deduce one from `a_text'
		require
			a_list_not_void: a_list /= Void
			a_text_not_empty: a_text /= Void and then not a_text.is_empty
		do
			if a_text ~ "AUTH=LOGIN" then
				a_list.extend(get_command(Login_action))
			end
		end
end
