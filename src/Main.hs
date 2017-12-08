module Main where

import Control.Monad(replicateM, forever)

data Neuron = OpenNeuron Double Double | ConnectedNeuron Double Double Double [Double] 
  deriving(Show)

data Network = ConnectedNetwork [Neuron] Network | OpenNetwork [Neuron]
  deriving(Show)

-- Accessors

netActivation :: Neuron -> Double
netActivation (OpenNeuron a _) = a
netActivation (ConnectedNeuron a _ _ _) = a

bruttoActivation :: Neuron -> Double
bruttoActivation (OpenNeuron _ a) = a
bruttoActivation (ConnectedNeuron _ a _ _) = a

neuronBias :: Neuron -> Double
neuronBias OpenNeuron{} = error "Open Neurons has no Bias"
neuronBias (ConnectedNeuron _ _ a _) = a

neuralScalars :: Neuron -> [Double]
neuralScalars OpenNeuron{} = error "Open neurons has no connections"
neuralScalars (ConnectedNeuron _ _ _ a) = a

networkNeurons :: Network -> [Neuron]
networkNeurons (ConnectedNetwork a _) = a
networkNeurons (OpenNetwork a) = a

-- Updaters

updateNetActivation :: Neuron -> Double -> Neuron
updateNetActivation (OpenNeuron _ b) a = OpenNeuron a b
updateNetActivation (ConnectedNeuron _ b c d) a = ConnectedNeuron a b c d

updateBruttoActivation :: Neuron -> Double -> Neuron
updateBruttoActivation (OpenNeuron a _) b = OpenNeuron a b
updateBruttoActivation (ConnectedNeuron a _ c d) b = ConnectedNeuron a b c d

updateScalars :: Neuron -> [Double] -> Neuron
updateScalars OpenNeuron{} _ = error "Open neuron has no weights, thus cant update"
updateScalars (ConnectedNeuron a b c _) d = ConnectedNeuron a b c d

-- Generators

openNeuronGenerator :: [Neuron]
openNeuronGenerator = cycle [OpenNeuron 0.5 0.5]

connectedNeuronGenerator :: [[Double] -> Neuron]
connectedNeuronGenerator = cycle [ConnectedNeuron 0.5 0.5 10]

seamlessInitialConnectionValues :: [Double]
seamlessInitialConnectionValues = cycle [0.5]

-- Network Creating

networkPropagationInitializer :: [Int] -> Network
networkPropagationInitializer (previous:current:next:rest) = 
    let nextNetwork = networkPropagationInitializer (current:next:rest) 
        connections = take previous seamlessInitialConnectionValues
        currentNeurons = map (\initializer -> initializer connections) (take current connectedNeuronGenerator)
    in (ConnectedNetwork currentNeurons nextNetwork)

networkPropagationInitializer (previous:current:[]) = 
    let connections = take previous seamlessInitialConnectionValues
        currentNeurons = map (\initializer -> initializer connections) (take current connectedNeuronGenerator)
    in (OpenNetwork currentNeurons)


networkInitializer :: [Int] -> Network
networkInitializer schematic@(inputNodes:_) = ConnectedNetwork (take inputNodes openNeuronGenerator) (networkPropagationInitializer schematic) 

-- Actual Functionalities

networkFold :: (Network -> Network -> Network) -> Network -> Network -> Network
networkFold f a net@(ConnectedNetwork _ network) = networkFold f (f a net) network
networkFold f a net@(OpenNetwork _) = f a net

networkFmap :: (Neuron -> Neuron) -> Network -> Network
networkFmap f (ConnectedNetwork neurons network) = ConnectedNetwork (map f neurons) network
networkFmap f (OpenNetwork neurons) = OpenNetwork (map f neurons)


-- Neuron Activation

activateBrutto :: (Double -> Double -> Double) -> [Neuron] -> Neuron -> Neuron
activateBrutto f neurons neuron = updateNeuron . sum $ zipWith f (neuralScalars neuron) connectionActivities
    where updateNeuron = updateBruttoActivation neuron
          connectionActivities = map netActivation neurons

activateNeuron :: (Double -> Double -> Double) -> (Double -> Double) -> [Neuron] -> Neuron -> Neuron
activateNeuron f sq neurons neuron = updateNeuron $ sq $ bruttoActivation bruttoUpdate
    where updateNeuron = updateNetActivation neuron
          bruttoUpdate = activateBrutto f neurons neuron


-- Network Activation

forwardPropagation :: (Double -> Double -> Double) -> (Double -> Double) -> Network -> Network -> Network
forwardPropagation f sq acc next = networkFmap activateNeuron' next
    where activateNeuron' = activateNeuron f sq (networkNeurons acc)

networkPropagation :: (Double -> Double -> Double) -> (Double -> Double) -> Network -> Network
networkPropagation f sq input@(ConnectedNetwork _ network) = networkFold propagation input network
    where propagation = forwardPropagation f sq

networkPropagation _ _ net@(OpenNetwork{}) = net

-- Querying Network

initializeNetworkQuery :: Network -> [Double] -> Network
initializeNetworkQuery (ConnectedNetwork neurons network) input = ConnectedNetwork activatedNeurons network
    where activatedNeurons = zipWith updateNetActivation neurons input

initializeNetworkQuery (OpenNetwork neurons) input = OpenNetwork activatedNeurons
    where activatedNeurons = zipWith updateNetActivation neurons input

networkQuery :: (Double -> Double -> Double) -> (Double -> Double) -> Network -> [Double] -> [Double]
networkQuery f sq net inp = map netActivation . networkNeurons $ networkPropagation f sq initializedNetwork
    where initializedNetwork = initializeNetworkQuery net inp


standardQuery :: Network -> [Double] -> [Double]
standardQuery = networkQuery (*) squish


-- Learning


neuronGradientDecent :: Double -> Neuron -> (Neuron, Double)
neuronGradientDecent totalError neuron = (updateScalars neuron updatedWeigths, derror * dsq)
    where derror = dcostFunction (netActivation neuron) totalError
          dsq = dsquish (netActivation neuron)

        --   This is where i apply the chain rule for each Weigth 
        --  derror is dTotalCost/dOutput, 
        --  dsq is dOutput/dInput 
        --  and weigth is dInput/dWeigth 
        --  The result equals dTotalCost/dWeigth times a learningRate
          offset = map (\weigth -> derror * dsq * weigth * learningRate) (neuralScalars neuron)

          updatedWeigths = zipWith (-) (neuralScalars neuron) offset




neuronGradientPropagation :: [Neuron] -> [Double] -> Neuron -> Int -> (Neuron, Double)
neuronGradientPropagation connections errors neuron index = (updateScalars neuron updatedWeigths, errorDoutput * outputDinput)
    where connections' = map (!!index) . map (neuralScalars) $ connections
        -- Rate of change of total Error with respect to this neurons output
          errorDoutput = sum $ zipWith (*) connections' errors
        
        -- Rate of change of This neurons output with respect to its input
          outputDinput = dsquish (netActivation neuron)

          --Same as the NeuronGradientDecent but instead to calculate
          --The error with respect to the weight we use the fact that
          --The Error with Respect to the previous nodes input is already calculated
          --Using that we calculate the error with respect to output for
          --All of the nodes this node is connected to and sum them up.
          --That'll be the error with respect to this nodes output
          --Multiplying that with the rate of change of the output
          --With respect to the input gives dError/dIput
          --Which in turn is used to adjust all the weights

          -- This because dInput/dWeigth == weigth
          -- THat's why weight * dError/dInput = dError/dWeigth
          -- which gives the direction to minimize the cost
          offset = map (\weigth -> errorDoutput * outputDinput * weigth * learningRate) (neuralScalars neuron)

          updatedWeigths = zipWith (-) (neuralScalars neuron) offset


backPropagation :: Network -> Double -> (Network, [Double])
backPropagation (OpenNetwork neurons) totalError = 
  let (neurons', errors') = unzip $ map (neuronGradientDecent totalError) neurons
    in (OpenNetwork neurons', errors')

backPropagation (ConnectedNetwork neurons network) totalError = 
  let (network', perrors) = backPropagation network totalError
      neuronGradientPropagation' = neuronGradientPropagation (networkNeurons network') perrors
      (neurons', errors') = unzip $ zipWith neuronGradientPropagation' neurons [0..] 
    in (ConnectedNetwork neurons' network', errors')
    

learn :: Network -> Double -> Network
learn (ConnectedNetwork neurons network) totalError = 
  let (network', _) = backPropagation network totalError
    in ConnectedNetwork neurons network'

outputCost :: [Double] -> [Double] -> Double
outputCost output expected = sum $ zipWith costFunction output expected

costFunction :: Double -> Double -> Double
costFunction output expected = (output - expected) * (output - expected)

dcostFunction :: Double -> Double -> Double
dcostFunction output expected =  -(output - expected) - (output - expected)

squish :: Double -> Double
squish val = exp val / (exp val + 1)

dsquish :: Double -> Double
dsquish val = squish val * (1 - squish val)

learningRate :: Double
learningRate = 5


main :: IO ()
main = do
    putStrLn "Please Enter How Many Layers: "
    times <- readLn
    schematic <- replicateM times 
                     (do putStrLn "Please Enter how many Neurons in this layer: "
                         readLn :: IO Int) -- type annotation to remove ambiguity

    putStrLn "How many output neurons is there? "
    times' <- readLn

    expected <- replicateM times' 
                     (do putStrLn "Please Enter Correct Answer for this Neuron: "
                         readLn :: IO Double) -- type annotation to remove ambiguity

    

    putStrLn "Please Enter How Many Input Neurons there Are: "
    imp <- readLn

    input <- replicateM imp
                     (do putStrLn "Please Enter Input: "
                         readLn :: IO Double) -- type annotation to remove ambiguity


    
    putStrLn "Creating Network"
    let network = networkInitializer schematic
    putStrLn "This is the Network"
    print network


    putStrLn "Querying Network"
    let response = standardQuery network input
    putStrLn "Network responded with"
    print response

    putStrLn "The cost is"
    let cost = outputCost response expected 
    print cost


    putStrLn "Commencing Super Awesome Learning Shit"
    let neonetwork = learn network cost
    putStrLn "New Network"
    print neonetwork

    putStrLn "Querying Network Again"
    let response' = standardQuery neonetwork input

    putStrLn "New Response and Cost is"

    print response'
    let cost' = outputCost response' expected

    print cost'

    putStrLn "Improved by"
    print $ cost / cost'




    

    



    


    


    
    print expected
        

