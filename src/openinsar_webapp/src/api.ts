export const getAuthToken = async (username: string, password: string) => {
    // let token = localStorage.getItem('authToken')
    let token = null

    if (!token) {
        // const username = window.prompt('Enter your username')
        // const password = window.prompt('Enter your password')

        const response = await fetch('/api/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ username, password })
        })
        
        if (!response.ok) {
            throw new Error('Failed to log in')
        }

        const data = await response.json()

        // Check data has a token
        if (!data.token) {
            throw new Error('Received invalid data')
        } else {
            token = data.token
            // Check token is a string
            if (typeof token !== 'string') {
                throw new Error('Received invalid data type')
            }
            // Store the token in localStorage
            localStorage.setItem('authToken', token)
            console.log(token)
        }
    }

    return token
}
