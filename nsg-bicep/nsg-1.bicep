targetScope = 'resourceGroup'

param nsgName string
param location string

// Import shared rules from JSON file
// var sharedRules = json(loadTextContent('./shared-rules.json')).securityRules

// Add custom rules specific to this NSG
var customRules = [
  {
    name: 'Allow_Internet_HTTPS_Inbound'
    properties: {
      description: 'Allow inbound internet connectivity for HTTPS only.'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      priority: 400
      direction: 'Inbound'
    }
  }
]

// Define the NSG resource
resource nsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: nsgName
  location: location
  properties: {
    // Combine shared and custom rules
    // securityRules: concat(sharedRules, customRules)
    securityRules: concat(customRules)
  }
}
