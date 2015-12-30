note
	description: "Summary description for {IL_IMAP_ACTION}."
	author: ""
	date: "$Date$"
	revision: "$Revision$"

class
	IL_IMAP_ACTION

feature -- Access

	Login_action: NATURAL = 1
	Capability_action: NATURAL = 2
	Select_action: NATURAL = 3
	Create_action: NATURAL = 13
	Delete_action: NATURAL = 12
	Rename_action: NATURAL = 4
	Subscribe_action: NATURAL = 5
	Unsubscribe_action: NATURAL = 6
	List_action: NATURAL = 11
	Lsub_action: NATURAL = 7
	Status_action: NATURAL = 8
	Noop_action: NATURAL = 9
	Logout_action: NATURAL = 10



	min_action: NATURAL = 1
	max_action: NATURAL = 13

feature -- Basic Operations

	get_command( a_action: NATURAL): STRING
			-- Returns the imap command corresponding to the action `a_action'
		require
			valid_action: a_action >= min_action and a_action <= max_action
		do
			inspect a_action
			when Login_action then
				Result := "LOGIN"
			when Capability_action then
				Result := "CAPABILITY"
			when Noop_action then
				Result := "NOOP"
			when Logout_action then
				Result := "LOGOUT"
			when Create_action then
				Result := "CREATE"
			when Delete_action then
				Result := "DELETE"
			when Rename_action then
				Result := "RENAME"
			when Subscribe_action then
				Result := "SUBSCRIBE"
			when Unsubscribe_action then
				Result := "UNSUBSCRIBE"
			when Select_action then
				Result := "SELECT"
			when List_action then
				Result := "LIST"
			when Lsub_action then
				Result := "LSUB"
			when Status_action then
				Result := "STATUS"
			else
				Result := ""
			end
		ensure
			result_set: not Result.is_empty
		end

feature {NONE} -- Implementation



end