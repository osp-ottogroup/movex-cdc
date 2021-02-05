describe('Main Page 01', () => {
    beforeEach(() => {
        cy.visit('/')
    })

    it('Check Connection', () => {
        cy.contains('User Name')
        cy.contains('Password')
        cy.contains('Login')
    })
    it('No Credentials', () => {
        cy.get('button').click()
        cy.contains('Login')
    })
    it('Wrong password', () => {
        cy.get('input[type=text]').type('admin')
        cy.get('input[type=password]').type('wrong')
        cy.get('button').click()
        cy.contains('wrong password', {timeout: 10000})
    })
    it('Unknown User', () => {
        cy.get('input[type=text]').type('idontexist')
        cy.get('input[type=password]').type('wrong')
        cy.get('button').click()
        cy.contains('No user found', {timeout: 10000})
    })
    it('Valid Login', () => {
        cy.get('input[type=text]').type('admin')
        cy.get('input[type=password]').type('test')
        cy.get('button').click()

        // login might take longer than 4s default timeout
        // TODO why does login take more than 4s often? Test for performance critera?
        cy.get('.navbar-item', {timeout: 10000}).contains('TriXX')
    })
})