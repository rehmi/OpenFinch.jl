import pygame
import random

class robotsGame:
   def __init__ ( self , screen , startingRobots ):
      self.screen = screen

      self.grid = dict()
      for y in range ( 25 ):
         for x in range ( 50 ):
            self.grid [ ( x , y ) ] = None

      self.robots = list()
      for i in range ( startingRobots ):
         while 1:
            x = random.randrange ( 0 , 50 )
            y = random.randrange ( 0 , 25 )

            if ( x , y ) not in self.robots:
               self.robots.append ( ( x , y ) )
               self.grid [ ( x , y ) ] = "ROBOT"
               break

      while 1:
         x = random.randrange ( 0 , 50 )
         y = random.randrange ( 0 , 25 )

         if self.checkGrid ( ( x , y ) ) == False:
            self.grid [ ( x , y ) ] = "PLAYER"
            self.playerX = x
            self.playerY = y
            break

      self.legend()

   def legend ( self ):
      pygame.draw.rect ( self.screen , ( 255 , 0 , 0 ) , ( 50 , 550 , 20 ,20 ) , 0 )   # Robot
      pygame.draw.rect ( self.screen , ( 0 , 255 , 0 ) , ( 50 , 580 , 20 ,20 ) , 0 )   # You
      pygame.draw.rect ( self.screen , ( 255 , 255 , 0 ) , ( 50 , 610 , 20 ,20 ) , 0 ) # Rubble

      pygame.font.init()
      font = pygame.font.SysFont ( "" , 20 )

      robotLabel = font.render ( "Robots" , True , ( 0 , 255 , 0 ) )
      playerLabel = font.render ( "Player" , True , ( 0 , 255 , 0 ) )
      rubbleLabel = font.render ( "Rubble" , True , ( 0 , 255 , 0 ) )
      moveLabel = font.render ( "Move with Q, W, E, A, D, Z, X, C or the arrowkeys" , True , ( 0 , 255 , 0 ) )
      teleportLabel = font.render ( "Teleport with T" , True , ( 0 , 255 ,0 ) )

      self.screen.blit ( robotLabel , ( 75 , 550 ) )
      self.screen.blit ( playerLabel , ( 75 , 580 ) )
      self.screen.blit ( rubbleLabel , ( 75 , 610 ) )
      self.screen.blit ( moveLabel , ( 550 , 550 ) )
      self.screen.blit ( teleportLabel , ( 550 , 580 ) )

   def drawGrid ( self ):
      for y in range ( 25 ):
         for x in range ( 50 ):
            pygame.draw.rect ( self.screen , ( 0 , 0 , 255 ) , ( ( x * 20 ) ,( y * 20 ) , 20 , 20 ) , 1)
            if self.grid [ ( x , y ) ] == "ROBOT":
               pygame.draw.rect ( self.screen , ( 255 , 0 , 0 ) , ( ( x * 20 )+ 1 , ( y * 20 ) + 1 , 18 , 18 ) , 0 )
            elif self.grid [ ( x , y ) ] == "PLAYER":
               pygame.draw.rect ( self.screen , ( 0 , 255 , 0 ) , ( ( x * 20 )+ 1 , ( y * 20 ) + 1 , 18 , 18 ) , 0 )
            elif self.grid [ ( x , y ) ] == "RUBBLE":
               pygame.draw.rect ( self.screen , ( 255 , 255 , 0 ) , ( ( x *20 ) + 1 , ( y * 20 ) + 1 , 18 , 18 ) , 0 )
            else:
               pygame.draw.rect ( self.screen , ( 0 , 0 , 0 ) , ( ( x * 20 ) +1 , ( y * 20 ) + 1 , 18 , 18 ) , 0 )

      pygame.display.flip()

   def checkWinLose ( self ):
      mycount = 0
      for index , bot in enumerate ( self.robots ):
#DBG         print("checkWinLose", index, bot, self.grid [ bot ], "mycount =",mycount)
         if self.grid [ bot ] == "ROBOT":
            mycount += 1

#DBG      print("nRobots =", mycount)
      if mycount == 0:
         return "WIN"
      elif ( self.playerX , self.playerY ) in self.robots:
         return "LOSE"
      else:
         return None

   def moveBots ( self ):
      for index , bot in enumerate ( self.robots ):
#DBG         print "move bot", index, bot,

         if self.grid [ bot ] == "RUBBLE":
#DBG            print " rubble"
            continue

         self.grid [ bot ] = ""

         botx , boty = bot
#         botx = bot [ 0 ]
#         boty = bot [ 1 ]
         if botx  > self.playerX: botx -= 1
         elif botx < self.playerX: botx += 1

         if boty > self.playerY: boty -= 1
         elif boty < self.playerY: boty += 1

         bot = ( botx , boty )

         self.robots [ index ] = bot
#DBG         print " to", bot

         if self.grid [ bot ] == "PLAYER":
            return

         if self.grid [ bot ] == "ROBOT":
            self.grid [ bot ] = "RUBBLE"
#DBG            print "Collision"
#DBG            for j , jbot in enumerate ( self.robots ):
#DBG               if j == index:
#DBG                  continue
#DBG               if bot == jbot:
#DBG                  print "Collision with", j, jbot

         if self.grid [ bot ] == "RUBBLE":
            continue

         self.grid [ bot ] = "ROBOT"

   def checkGrid ( self , position ):
      result = False
      # Check left
      check = ( position [ 0 ] - 1 , position [ 1 ] )
      if check in self.robots: result = True
      # Check right
      check = ( position [ 0 ] + 1 , position [ 1 ] )
      if check in self.robots: result = True
      # Check up
      check = ( position [ 0 ] , position [ 1 ] - 1 )
      if check in self.robots: result = True
      # Check down
      check = ( position [ 0 ] , position [ 1 ] + 1 )
      if check in self.robots: result = True

      return result

   def run ( self ):
      running = True
      while running:
         for event in pygame.event.get():
            if event.type == pygame.KEYDOWN:
               if event.key == pygame.K_DOWN or event.key == ord ( "x" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerY += 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == pygame.K_UP or event.key == ord ( "w" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerY -= 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == pygame.K_RIGHT or event.key == ord ( "d" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX += 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == pygame.K_LEFT or event.key == ord ( "a" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX -= 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "e" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX += 1
                  self.playerY -= 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "q" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX -= 1
                  self.playerY -= 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "z" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX -= 1
                  self.playerY += 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "c" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX += 1
                  self.playerY += 1
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "t" ):
                  self.grid [ ( self.playerX , self.playerY ) ] = ""
                  self.playerX = random.randrange ( 1 , 50 )
                  self.playerY = random.randrange ( 1 , 25 )
                  self.grid [ ( self.playerX , self.playerY ) ] = "PLAYER"
               elif event.key == ord ( "p" ):
                  running = False
               self.moveBots()
               over = self.checkWinLose()
               if over != None:
                  if over == "WIN": print("You survived!")
                  elif over == "LOSE": print("Looks like the robots got you this time!")
                  running = False

#DBG                  print "Player", self.playerX, self.playerY
#DBG                  for index , bot in enumerate ( self.robots ):
#DBG                     print "bot", index, bot, self.grid [ bot ]

               self.drawGrid()

pygame.display.init()
screen = pygame.display.set_mode ( ( 1024 , 768 ) )

game = robotsGame ( screen , 25 )
game.drawGrid()
game.run()