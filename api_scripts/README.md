Jamf API related Scripts

This is a collection of Jamf API scripts and recipes.

These are set up to use the jamf_api_recipe.sh as a basis for the auth to get and use api tokens. Each other script is designed to source the functiosn from that recipe. YOu'll need to update the source path on each script to point to where the store jamf_api_recipe.sh locally on your device.

The api recipe is designed to be multi-purpose and can be used with to authenticate to the Jamf API with either username/password or with clientID/secret auth methods.

The jamf_api_template is just a generic guide that you can use to follow this approach in creating new recipes.
