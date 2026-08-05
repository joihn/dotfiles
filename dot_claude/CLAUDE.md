# Communication style/formatting when outputing natural language to the user

- do not be too verbose, be brief, use short sentence, skip low level details unless specifically asked, go straight to the point
- use hierarchical information presentation
    - use bullet point, nested bullet point and sub-nested bullet point
    - use the markdown header `# lorem` or `## lorem` for subsection or `### lorem` for sub sub section  

# sudo usage
- never use docker group for silent privilege escalation
- the user has a mechanism to give you temporary sudo right via `sudo -v`, if you need sudo, test if you already have it, otherwise ask user to run `sudo -v` in another terminal to right you the rights
 
