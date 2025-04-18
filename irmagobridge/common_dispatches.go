package irmagobridge

import (
	"encoding/json"

	irma "github.com/AVecsi/pq-irmago"
)

// needed to inject logo into issuers
type WrappedConfiguration irma.Configuration
type WrappedCredentialType struct {
	Logo string `json:",omitempty"`
	irma.CredentialType
}

func (conf *WrappedConfiguration) MarshalJSON() ([]byte, error) {
	var encodedData struct {
		CredentialTypes map[irma.CredentialTypeIdentifier]*WrappedCredentialType
		irma.Configuration
	}

	encodedData.Configuration = *(*irma.Configuration)(conf)
	encodedData.CredentialTypes = make(map[irma.CredentialTypeIdentifier]*WrappedCredentialType)

	for k, v := range conf.CredentialTypes {
		if v == nil {
			encodedData.CredentialTypes[k] = nil
			continue
		}
		encodedData.CredentialTypes[k] = &WrappedCredentialType{
			Logo:           v.Logo((*irma.Configuration)(conf)),
			CredentialType: *v,
		}
	}

	return json.Marshal(encodedData)
}

func dispatchConfigurationEvent() {
	t := WrappedConfiguration(*client.Configuration)
	dispatchEvent(&irmaConfigurationEvent{
		IrmaConfiguration: &t,
	})
	dispatchCredentialsEvent()
}

func dispatchCredentialsEvent() {
	bridge.DebugLog("\n\n\n\n\n dispatchCredentialsEvent is coming from")
	dispatchEvent(&credentialsEvent{
		Credentials: client.CredentialInfoList(),
	})
}

func dispatchEnrollmentStatusEvent() {
	dispatchEvent(&enrollmentStatusEvent{
		EnrolledSchemeManagerIds:   client.EnrolledSchemeManagers(),
		UnenrolledSchemeManagerIds: client.UnenrolledSchemeManagers(),
	})
}

func dispatchPreferencesEvent() {
	dispatchEvent(&clientPreferencesEvent{
		Preferences: client.Preferences,
	})
}
